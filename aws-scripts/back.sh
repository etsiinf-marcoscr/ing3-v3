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
BACKEND_PATH="$PROJECT_ROOT/eventhub-back-springboot"

# PublicIp lo dejó ec2.sh en lab-state.json.
PUBLIC_IP=$(state_require PublicIp)

if [ ! -f "$KEY_PATH" ]; then
    echo "Error: No se encontró la clave SSH en: $KEY_PATH"
    exit 1
fi

if [ ! -d "$BACKEND_PATH" ]; then
    echo "Error: No se encontró el proyecto backend en: $BACKEND_PATH"
    exit 1
fi

if ! command -v mvn > /dev/null; then
    echo "Error: mvn no está en el PATH. Ejecuta setup.sh o 'source /etc/profile.d/dev-env.sh'."
    exit 1
fi

# Versión mayor de Java con la que compila Maven (25, 21, ...).
# El runtime de la EC2 de destino debe ser igual o superior.
JAVA_MAJOR=$(mvn -v | awk -F': ' '/^Java version/ {split($2, a, /[.,]/); print a[1]; exit}')
if [ -z "$JAVA_MAJOR" ]; then
    echo "Error: no se pudo detectar la versión de Java que usa Maven."
    exit 1
fi
echo "Java de compilación: $JAVA_MAJOR"

# URL JDBC de Aurora. El secreto rds!cluster-... (contraseña gestionada por RDS) solo trae
# username y password, y application.properties usa ${host}:${port}, que quedan sin resolver.
# Se pasa la URL completa como variable de entorno, que tiene prioridad sobre application.properties.
DB_CLUSTER_ID="${DB_CLUSTER_ID:-eventhub-cluster-aurora}"
DB_INFO=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$DB_CLUSTER_ID" \
    --query 'DBClusters[0].[Endpoint,Port,DatabaseName]' \
    --output text)
read -r DB_HOST DB_PORT DB_NAME <<< "$DB_INFO"
if [ -z "$DB_HOST" ] || [ "$DB_HOST" = "None" ] || [ -z "$DB_NAME" ] || [ "$DB_NAME" = "None" ]; then
    echo "Error: no se pudo obtener endpoint/base de datos del cluster '$DB_CLUSTER_ID' (resultado: $DB_INFO)."
    exit 1
fi
DB_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "Base de datos: $DB_URL"

echo "Compilando el backend Spring Boot..."
cd "$BACKEND_PATH"
mvn clean package -DskipTests
BACKEND_JAR_NAME=$(find target -maxdepth 1 -type f -name '*.jar' ! -name '*.original' -print -quit)
cd - > /dev/null
BACKEND_JAR="$BACKEND_PATH/$BACKEND_JAR_NAME"

if [ -z "$BACKEND_JAR_NAME" ] || [ ! -f "$BACKEND_JAR" ]; then
    echo "Error: No se encontró el JAR ejecutable del backend."
    exit 1
fi

echo "Subiendo el backend a $PUBLIC_IP..."

# -i: clave SSH de AWS Academy (labsuser.pem)
# -o StrictHostKeyChecking=no: el laboratorio no pide confirmar known_hosts
scp -o StrictHostKeyChecking=no -i "$KEY_PATH" "$BACKEND_JAR" ubuntu@"$PUBLIC_IP":/tmp/eventhub.jar

echo "Configurando Spring Boot en la instancia EC2 (Java $JAVA_MAJOR)..."

# -T: sin pseudo-terminal, para que no avise al leer el script por stdin
# JAVA_MAJOR se pasa como variable de entorno al bash remoto (el heredoc va entrecomillado).
ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" "JAVA_MAJOR=$JAVA_MAJOR DB_URL=$DB_URL bash -s" << 'END_BACKEND'
set -e
sudo apt-get update -y

# Java: primero OpenJDK de los repos de Ubuntu; si esa versión no existe, Corretto (repo oficial de Amazon).
OPENJDK_PKG="openjdk-${JAVA_MAJOR}-jre-headless"
CANDIDATE=$(apt-cache policy "$OPENJDK_PKG" 2>/dev/null | awk '/Candidate:/ {print $2}')
if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "(none)" ]; then
    sudo apt-get install -y "$OPENJDK_PKG"
else
    echo "$OPENJDK_PKG no disponible en apt; usando Amazon Corretto $JAVA_MAJOR"
    sudo apt-get install -y wget gnupg ca-certificates
    wget -qO - https://apt.corretto.aws/corretto.key | sudo gpg --dearmor --yes -o /usr/share/keyrings/corretto-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/corretto-keyring.gpg] https://apt.corretto.aws stable main" | sudo tee /etc/apt/sources.list.d/corretto.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y "java-${JAVA_MAJOR}-amazon-corretto-jdk"
fi
java -version

# En el primer despliegue el servicio aún no existe.
sudo systemctl stop eventhub 2>/dev/null || true
sudo systemctl disable eventhub 2>/dev/null || true
sudo rm -f /etc/systemd/system/eventhub.service
sudo rm -rf /opt/eventhub
sudo mkdir -p /opt/eventhub
sudo mv /tmp/eventhub.jar /opt/eventhub/eventhub.jar
sudo chown -R ubuntu:ubuntu /opt/eventhub
# Heredoc sin comillas: se expande $DB_URL (en la unidad no hay más '$').
sudo tee /etc/systemd/system/eventhub.service > /dev/null << SERVICE
[Unit]
Description=Event Hub Spring Boot backend
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/opt/eventhub
Environment="SPRING_DATASOURCE_URL=$DB_URL"
ExecStart=/usr/bin/java -jar /opt/eventhub/eventhub.jar
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable eventhub
sudo systemctl restart eventhub

# restart devuelve 0 aunque la app caiga al arrancar, y Restart=always la relanza en bucle,
# así que "is-active" no basta. Esperamos hasta 90 s a que Tomcat escuche en el 8080
# (Spring Boot solo abre el puerto cuando el contexto ha arrancado bien).
for i in $(seq 1 45); do
    if ss -ltn | grep -q ':8080 '; then
        break
    fi
    sleep 2
done
if ! ss -ltn | grep -q ':8080 '; then
    echo "Error: eventhub no llegó a escuchar en el puerto 8080 (reinicios: $(systemctl show eventhub -p NRestarts --value))." >&2
    echo "Líneas relevantes del log:" >&2
    sudo journalctl -u eventhub -n 300 --no-pager | grep -E "ERROR|WARN|Caused by|HHH" | tail -n 20 >&2 || true
    exit 1
fi
echo "eventhub escuchando en el puerto 8080."
END_BACKEND

echo "El JAR queda en la instancia, como servicio systemd. No va en el repositorio:"
echo "  https://$PUBLIC_IP/api/eventos"
echo "Despliegue del backend finalizado."