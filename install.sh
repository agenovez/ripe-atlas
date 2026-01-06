#!/usr/bin/env bash
set -euo pipefail

########################################
# Configuration
########################################
STACK_NAME="ripe-atlas"
BASE_DIR="/opt/docker/${STACK_NAME}"
ENV_FILE="${BASE_DIR}/.env"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"

DATA_ETC="/etc/ripe-atlas"
DATA_RUN="/run/ripe-atlas"
DATA_SPOOL="/var/spool/ripe-atlas"

ENABLE_SYSTEMD="yes"

########################################
# Safety checks
########################################
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

########################################
# Install Docker if missing
########################################
if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release

  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
else
  echo "Docker already installed."
fi

########################################
# Install Docker Compose plugin if missing
########################################
if ! docker compose version >/dev/null 2>&1; then
  echo "Installing Docker Compose plugin..."
  apt-get install -y docker-compose-plugin
else
  echo "Docker Compose plugin already installed."
fi

########################################
# Create directories
########################################
echo "Creating directory structure..."

mkdir -p "${BASE_DIR}"
mkdir -p "${DATA_ETC}" "${DATA_RUN}" "${DATA_SPOOL}"

chown -R root:root "${BASE_DIR}" "${DATA_ETC}" "${DATA_RUN}" "${DATA_SPOOL}"
chmod 750 "${BASE_DIR}"
chmod 755 "${DATA_ETC}" "${DATA_RUN}" "${DATA_SPOOL}"

########################################
# Create .env file
########################################
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Creating .env file..."
  cat > "${ENV_FILE}" <<EOF
TZ=UTC
RXTXRPT=yes
EOF
  chmod 600 "${ENV_FILE}"
fi

########################################
# Create docker-compose.yml
########################################
if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Creating docker-compose.yml..."
  cat > "${COMPOSE_FILE}" <<'EOF'
version: "3.9"

services:
  ripe-atlas:
    image: docker.io/jamesits/ripe-atlas:latest
    container_name: ripe-atlas
    restart: unless-stopped

    env_file:
      - .env

    network_mode: host

    volumes:
      - /etc/ripe-atlas:/etc/ripe-atlas
      - /run/ripe-atlas:/run/ripe-atlas
      - /var/spool/ripe-atlas:/var/spool/ripe-atlas

    cap_drop:
      - ALL
    cap_add:
      - NET_RAW
      - KILL
      - SETUID
      - SETGID
      - CHOWN
      - FOWNER
      - DAC_OVERRIDE

    mem_reservation: 64m
    mem_limit: 512m

    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

    security_opt:
      - no-new-privileges:true
EOF
fi

########################################
# Deploy container
########################################
echo "Deploying RIPE Atlas container..."
cd "${BASE_DIR}"
docker compose pull
docker compose up -d

########################################
# Optional systemd service
########################################
if [[ "${ENABLE_SYSTEMD}" == "yes" ]]; then
  SERVICE_FILE="/etc/systemd/system/${STACK_NAME}.service"

  if [[ ! -f "${SERVICE_FILE}" ]]; then
    echo "Creating systemd service..."
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=RIPE Atlas Probe (Docker)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=${BASE_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${STACK_NAME}"
    systemctl start "${STACK_NAME}"
  fi
fi

########################################
# Final status
########################################
echo
echo "Installation complete."
echo "Verify with:"
echo "  docker logs -f ripe-atlas"
echo
echo "Then register the probe at:"
echo "  https://atlas.ripe.net/"
