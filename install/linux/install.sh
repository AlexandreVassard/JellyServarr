#!/bin/bash
set -e

SERVICE_DIR="${SERVICE_DIR:-/etc/systemd/system}"
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
ENV_DIR="${ENV_DIR:-/etc}"
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

if [ ! -d "/etc/jellyfin-webdav" ]; then
    say "Creating Jellyfin WebDAV configuration folder..."
    mkdir -p "$ENV_DIR/jellyfin-webdav"
else
    say "Jellyfin WebDAV configuration folder exists, don't need to create it."
fi

RCLONE_CONF_FILE="$ENV_DIR/jellyfin-webdav/rclone.conf"
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
cp "${REPOSITORY_DIR}/.jellyfin-webdav.env.example" "$ENV_DIR/jellyfin-webdav/.env.default"

JELLYFIN_WEBDAV_ENV_FILE="$ENV_DIR/jellyfin-webdav/.env"
if [ ! -f "$JELLYFIN_WEBDAV_ENV_FILE" ]; then
    say "WARNING : No environment file found ($JELLYFIN_WEBDAV_ENV_FILE)."
    say "Default values in \"$ENV_DIR/jellyfin-webdav/.env.default\" will be used."
else
    say "\"$JELLYFIN_WEBDAV_ENV_FILE\" found."
    say "Default values in \"$ENV_DIR/jellyfin-webdav/.env.default\" will be overriden by \"$JELLYFIN_WEBDAV_ENV_FILE\"."
fi

say "Installing WebDAV services..."

say "Copying systemd service file..."
cp "${WORKING_DIR}/services/jellyfin-webdav.service" "$SERVICE_DIR/"

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
