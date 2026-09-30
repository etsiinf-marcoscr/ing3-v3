#!/bin/bash

# TODO: Hacer el script idempotente
# Hay que pasar la clave ssh a ssh-key/labsuser.pem antes de ejecutar este script y clonar el repo.
# Node.js 20 via NodeSource
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -

# Instalar Java
curl -fsSL https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.tar.gz -o /tmp/jdk25.tar.gz
sudo mkdir -p /usr/lib/jvm
sudo tar -xzf /tmp/jdk25.tar.gz -C /usr/lib/jvm
sudo ln -sf /usr/lib/jvm/jdk-25/bin/java /usr/bin/java
sudo ln -sf /usr/lib/jvm/jdk-25/bin/javac /usr/bin/javac
rm /tmp/jdk25.tar.gz
export JAVA_HOME=$(ls -d /usr/lib/jvm/jdk-25* | head -1)
export PATH=$JAVA_HOME/bin:$PATH

# Dependencias del sistema
sudo yum install -y maven git nodejs nginx openssl make jq aws-cli

# Habilitar nginx
sudo dnf install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx

# Permisos de ejecución a los scripts de despliegue
chmod +x aws-scripts/*.sh


