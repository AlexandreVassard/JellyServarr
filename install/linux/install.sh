#!/bin/bash
set -e

APP_BASE_DIR="${APP_BASE_DIR:-/opt/jellyfin-servarr}"
SERVICE_DIR="${SERVICE_DIR:-/etc/systemd/system}"
BIN_DIR="${BIN_DIR:-${APP_BASE_DIR}/bin}"
ENV_DIR="${ENV_DIR:-${APP_BASE_DIR}/config}"
WORKING_DIR="${WORKING_DIR:-$(readlink -f "$(dirname "$0")")}"
REPOSITORY_DIR="${REPOSITORY_DIR:-$(readlink -f "$WORKING_DIR/../..")}"

say() {
    echo >&2 "$(date '+%Y-%m-%d %H:%M:%S') >> $*"
}

if [[ $EUID -ne 0 ]]; then
    say "This script must be run as root. Try again with:"
    say "   sudo $0"
    exit 1
fi

say "Checking configuration files..."

if [ ! -d "${APP_BASE_DIR}/config" ]; then
    say "Creating Jellyfin WebDAV configuration folder..."
    mkdir -p "$ENV_DIR"
else
    say "Jellyfin WebDAV configuration folder exists, don't need to create it."
fi

RCLONE_CONF_FILE="$ENV_DIR/rclone.conf"
if [ ! -f "$RCLONE_CONF_FILE" ]; then
    say "No rclone configuration file found ($RCLONE_CONF_FILE)"
    say "Please create this file from the example: "
    say "   cp ${REPOSITORY_DIR}/rclone.conf.example $RCLONE_CONF_FILE"
    say "Then edit it to match your WebDAV provider settings."
    exit 1
else
    say "\"$RCLONE_CONF_FILE\" found."
fi

say "Copying default environment file..."
cp "${REPOSITORY_DIR}/.jellyfin-webdav.env.example" "$ENV_DIR/.env.default"

JELLYFIN_WEBDAV_ENV_FILE="$ENV_DIR/.env"
if [ ! -f "$JELLYFIN_WEBDAV_ENV_FILE" ]; then
    say "WARNING : No environment file found ($JELLYFIN_WEBDAV_ENV_FILE)."
    say "Default values in \"$ENV_DIR/.env.default\" will be used."
else
    say "\"$JELLYFIN_WEBDAV_ENV_FILE\" found."
    say "Default values in \"$ENV_DIR/.env.default\" will be overriden by \"$JELLYFIN_WEBDAV_ENV_FILE\"."
fi

say "Creating mount and data directories..."
mkdir -p \
    "${APP_BASE_DIR}/mnt/webdav" \
    "${APP_BASE_DIR}/mnt/movies" \
    "${APP_BASE_DIR}/mnt/series" \
    "${APP_BASE_DIR}/data/traefik/letsencrypt" \
    "${APP_BASE_DIR}/data/jellyfin/config" \
    "${APP_BASE_DIR}/data/prowlarr/config" \
    "${APP_BASE_DIR}/data/radarr/config" \
    "${APP_BASE_DIR}/data/sonarr/config" \
    "${APP_BASE_DIR}/data/jellyseerr/config" \
    "${APP_BASE_DIR}/data/tautulli/config" \
    "${APP_BASE_DIR}/data/rdtclient/db" \
    "${APP_BASE_DIR}/data/rdtclient/downloads"

say "Installing WebDAV services..."

say "Copying systemd service file..."
mkdir -p "$BIN_DIR"
sed "s|@@APP_BASE_DIR@@|${APP_BASE_DIR}|g" \
    "${WORKING_DIR}/services/jellyfin-webdav.service" \
    > "$SERVICE_DIR/jellyfin-webdav.service"

say "Copying jellyfin-webdav.sh script..."
cp "${WORKING_DIR}/scripts/jellyfin-webdav.sh" "$BIN_DIR/"
chmod +x "$BIN_DIR/jellyfin-webdav.sh"

say "Reloading systemd daemon..."
systemctl daemon-reload

say "Enabling service..."
systemctl enable jellyfin-webdav.service

say "Starting service..."
systemctl restart jellyfin-webdav.service

say "Installation complete."
