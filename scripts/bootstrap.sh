#!/bin/bash
set -e

REPO_URL="https://github.com/AlexandreVassard/JellyServarr.git"
INSTALL_DIR="${INSTALL_DIR:-/opt/jellyservarr}"

say() {
    echo >&2 "$(date '+%Y-%m-%d %H:%M:%S') >> $*"
}

if [[ $EUID -ne 0 ]]; then
    say "This script must be run as root. Try again with:"
    say "   curl -fsSL https://raw.githubusercontent.com/AlexandreVassard/JellyServarr/main/scripts/bootstrap.sh | sudo bash"
    exit 1
fi

say "Installing JellyServarr to ${INSTALL_DIR}..."

if [ -d "${INSTALL_DIR}/.git" ]; then
    say "Repository already present — pulling latest changes..."
    git -C "${INSTALL_DIR}" pull
else
    say "Cloning repository..."
    git clone "${REPO_URL}" "${INSTALL_DIR}"
fi

say "Copying example configuration files..."

ENV_FILE="${INSTALL_DIR}/.env"
if [ ! -f "${ENV_FILE}" ]; then
    cp "${INSTALL_DIR}/.env.example" "${ENV_FILE}"
    say "Created ${ENV_FILE}"
else
    say "${ENV_FILE} already exists, skipping."
fi

RCLONE_CONF_DIR="${INSTALL_DIR}/config"
RCLONE_CONF_FILE="${RCLONE_CONF_DIR}/rclone.conf"
mkdir -p "${RCLONE_CONF_DIR}"
if [ ! -f "${RCLONE_CONF_FILE}" ]; then
    cp "${INSTALL_DIR}/rclone.conf.example" "${RCLONE_CONF_FILE}"
    say "Created ${RCLONE_CONF_FILE}"
else
    say "${RCLONE_CONF_FILE} already exists, skipping."
fi

cat >&2 <<EOF

$(date '+%Y-%m-%d %H:%M:%S') >> -------------------------------------------------------
$(date '+%Y-%m-%d %H:%M:%S') >> JellyServarr downloaded to ${INSTALL_DIR}
$(date '+%Y-%m-%d %H:%M:%S') >>
$(date '+%Y-%m-%d %H:%M:%S') >> Before starting, configure two files:
$(date '+%Y-%m-%d %H:%M:%S') >>
$(date '+%Y-%m-%d %H:%M:%S') >>   1. ${ENV_FILE}
$(date '+%Y-%m-%d %H:%M:%S') >>      Set TRAEFIK_HOST, PUID/PGID, TZ, HOMER_LOCAL_IP, WEBDAV_PATH
$(date '+%Y-%m-%d %H:%M:%S') >>
$(date '+%Y-%m-%d %H:%M:%S') >>   2. ${RCLONE_CONF_FILE}
$(date '+%Y-%m-%d %H:%M:%S') >>      Set your WebDAV URL, user, and obscured password.
$(date '+%Y-%m-%d %H:%M:%S') >>      Obscure your password with:
$(date '+%Y-%m-%d %H:%M:%S') >>        docker run --rm rclone/rclone:latest obscure 'your_password'
$(date '+%Y-%m-%d %H:%M:%S') >>
$(date '+%Y-%m-%d %H:%M:%S') >> Then run:
$(date '+%Y-%m-%d %H:%M:%S') >>   sudo APP_BASE_DIR=${INSTALL_DIR} bash ${INSTALL_DIR}/scripts/install.sh
$(date '+%Y-%m-%d %H:%M:%S') >> -------------------------------------------------------

EOF
