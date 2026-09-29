#!/bin/bash

# Compila la SPA y la publica en /var/www/html de la instancia.
# No tiene delete: el build desaparece con la instancia.
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

echo "Clonando el repositorio y compilando el frontend en EC2..."

# PUBLIC_IP se expande localmente; no se comilla END_BUILD para permitirlo.
ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ec2-user@"$PUBLIC_IP" << END_BUILD
set -e
sudo yum update -y
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo yum install -y nodejs git

sudo rm -rf /tmp/eventhub-front
git clone https://github.com/GRISE-UPM/muii-prof-2026 /tmp/eventhub-front
cd /tmp/eventhub-front/eventhub-front-react

# Vite solo carga este fichero con npm run build, no con npm run dev.
cat > .env.production.local << 'EOF'
# Generado por aws-scripts/front.sh. No editar a mano.
# VITE_API_BASE_URL: origen HTTPS de la API en EC2
VITE_API_BASE_URL=https://$PUBLIC_IP
EOF

npm install
npm run build

BUILD_DIR=/tmp/eventhub-front/eventhub-front-react/dist
if [ ! -d "\$BUILD_DIR" ]; then
    BUILD_DIR=/tmp/eventhub-front/eventhub-front-react/build
fi

# Sustituye la página de carga de nginx.sh por el frontend compilado.
sudo rm -rf /var/www/html/*
sudo mv "\$BUILD_DIR"/* /var/www/html/
sudo rm -rf /tmp/eventhub-front
sudo chmod -R 755 /var/www/html
END_BUILD

echo "El build queda en la instancia, servido por Nginx. No va en el repositorio:"
echo "  https://$PUBLIC_IP/"
echo "Despliegue del frontend finalizado."