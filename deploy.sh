#!/bin/bash
# Preparación del entorno en Amazon Linux 2023. Idempotente: se puede ejecutar varias veces.
# Antes de ejecutarlo: clonar el repo y copiar la clave SSH a ssh-key/labsuser.pem
set -euo pipefail
cd "$(dirname "$0")"

# ---- Versiones fijas (cambiar aquí) ----
JAVA_MAJOR=25
MAVEN_VERSION=3.9.9

log() { echo "==> $*"; }

# ---- Precondiciones ----
[ -f ssh-key/labsuser.pem ] || { echo "Falta ssh-key/labsuser.pem" >&2; exit 1; }
chmod 600 ssh-key/labsuser.pem

# ---- Paquetes del sistema (dnf es idempotente) ----
JAVA_PKG="java-${JAVA_MAJOR}-amazon-corretto-devel"
if ! dnf list --available "$JAVA_PKG" >/dev/null 2>&1 && ! rpm -q "$JAVA_PKG" >/dev/null 2>&1; then
  echo "El paquete $JAVA_PKG no está en los repos de este AMI. Ejecuta 'sudo dnf upgrade --releasever=latest' o cambia JAVA_MAJOR." >&2
  exit 1
fi

log "Instalando paquetes del sistema"
sudo dnf install -y "$JAVA_PKG" nodejs20 git nginx openssl make jq tar gzip

# ---- Maven con versión fija (evita que el paquete del repo arrastre otro JDK) ----
if [ ! -d "/opt/apache-maven-${MAVEN_VERSION}" ]; then
  log "Instalando Maven ${MAVEN_VERSION}"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -o "$tmp/maven.tar.gz"
  sudo tar -xzf "$tmp/maven.tar.gz" -C /opt
fi
sudo ln -sfn "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven
# En /usr/local/bin para que mvn esté disponible también en shells no interactivos (make, ssh "cmd", cron)
sudo ln -sfn /opt/maven/bin/mvn /usr/local/bin/mvn

# ---- Variables de entorno persistentes ----
log "Configurando JAVA_HOME y PATH"
sudo tee /etc/profile.d/dev-env.sh >/dev/null <<EOF
export JAVA_HOME=/usr/lib/jvm/java-${JAVA_MAJOR}-amazon-corretto
export MAVEN_HOME=/opt/maven
export PATH=\$JAVA_HOME/bin:\$MAVEN_HOME/bin:\$PATH
EOF
# shellcheck disable=SC1091
source /etc/profile.d/dev-env.sh

# ---- nginx ----
log "Habilitando nginx"
sudo systemctl enable --now nginx

# ---- Scripts de despliegue ----
chmod +x aws-scripts/*.sh

# ---- Verificación ----
log "Verificación"
node -v
java -version
mvn -v | head -1
command -v aws >/dev/null && aws --version || echo "AVISO: aws-cli no encontrado" >&2
echo "nginx: $(systemctl is-active nginx)"