#!/bin/bash

# TODO: Hacer el script idempotente
# Hay que pasar la clave ssh a ssh-key/labsuser.pem antes de ejecutar este script.

# Node.js 20 via NodeSource
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -

# Dependencias del sistema
sudo yum install -y java-21-amazon-corretto maven git nodejs nginx openssl make jq aws-cli

# Habilitar nginx
sudo dnf install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx

# Clonar el repositorio si no existe ya
if [ ! -d "eventhub-front-react" ]; then
    git clone https://github.com/GRISE-UPM/muii-prof-2026
fi

# Permisos de ejecución a los scripts de despliegue
chmod +x muii-prof-2026/aws-scripts/*.sh


