#!/bin/bash

# Compila el backend Spring Boot y lo arranca como servicio en la instancia.
# No tiene delete: el JAR y systemd desaparecen con la instancia.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"
KEY_PATH="$PROJECT_ROOT/ssh-key/labsuser.pem"

# PublicIp lo dejó ec2.sh en lab-state.json.
PUBLIC_IP=$(state_require PublicIp)

if [ ! -f "$KEY_PATH" ]; then
    echo "Error: No se encontró la clave SSH en: $KEY_PATH"
    exit 1
fi

echo "Clonando el repositorio y compilando el backend en EC2..."

# -T: sin pseudo-terminal, para que no avise al leer el script por stdin
ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" << 'END_BACKEND'
set -e
sudo apt-get update -y
sudo apt-get install -y git maven tar gzip

# Instalar JDK 25 desde Oracle (no está en los repos de Ubuntu)
curl -fsSL https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.tar.gz -o /tmp/jdk25.tar.gz
sudo mkdir -p /usr/lib/jvm
sudo tar -xzf /tmp/jdk25.tar.gz -C /usr/lib/jvm
rm /tmp/jdk25.tar.gz
export JAVA_HOME=$(ls -d /usr/lib/jvm/jdk-25* | head -1)
export PATH=$JAVA_HOME/bin:$PATH

sudo rm -rf /tmp/eventhub-back
git clone https://github.com/GRISE-UPM/muii-prof-2026 /tmp/eventhub-back
# Copiar cognito.properties generado por cognito.sh en el bastion
scp -o StrictHostKeyChecking=no -i "$KEY_PATH" \
    "$PROJECT_ROOT/eventhub-back-springboot/src/main/resources/cognito.properties" \
    ubuntu@"$PUBLIC_IP":/tmp/eventhub-back/eventhub-back-springboot/src/main/resources/cognito.properties
cd /tmp/eventhub-back/eventhub-back-springboot
mvn clean package -DskipTests

# En el primer despliegue el servicio aún no existe.
sudo systemctl stop eventhub 2>/dev/null || true
sudo systemctl disable eventhub 2>/dev/null || true
sudo rm -f /etc/systemd/system/eventhub.service
sudo rm -rf /opt/eventhub
sudo mkdir -p /opt/eventhub
sudo mv target/*.jar /opt/eventhub/eventhub.jar
sudo chown -R ubuntu:ubuntu /opt/eventhub
sudo rm -rf /tmp/eventhub-back

JAVA_BIN=$(ls -d /usr/lib/jvm/jdk-25*/bin/java | head -1)
sudo tee /etc/systemd/system/eventhub.service > /dev/null << SERVICE
[Unit]
Description=Event Hub Spring Boot backend
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/opt/eventhub
ExecStart=${JAVA_BIN} -jar /opt/eventhub/eventhub.jar
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable eventhub
sudo systemctl restart eventhub
END_BACKEND

echo "El JAR queda en la instancia, como servicio systemd. No va en el repositorio:"
echo "  https://$PUBLIC_IP/api/eventos"
echo "Despliegue del backend finalizado."