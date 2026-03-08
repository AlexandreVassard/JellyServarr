#!/bin/bash
set -e

APP_BASE_DIR="${APP_BASE_DIR:-/opt/jellyfin-servarr}"
WORKING_DIR="${WORKING_DIR:-$(readlink -f "$(dirname "$0")")}"
REPOSITORY_DIR="${REPOSITORY_DIR:-$(readlink -f "$WORKING_DIR/..")}"

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
    mkdir -p "${APP_BASE_DIR}/config"
else
    say "Jellyfin WebDAV configuration folder exists, don't need to create it."
fi

RCLONE_CONF_FILE="${APP_BASE_DIR}/config/rclone.conf"
if [ ! -f "$RCLONE_CONF_FILE" ]; then
    say "No rclone configuration file found ($RCLONE_CONF_FILE)"
    say "Please create this file from the example: "
    say "   cp ${REPOSITORY_DIR}/rclone.conf.example $RCLONE_CONF_FILE"
    say "Then edit it to match your WebDAV provider settings."
    exit 1
else
    say "\"$RCLONE_CONF_FILE\" found."
fi

if systemctl is-active --quiet jellyfin-webdav.service 2>/dev/null; then
    say "Stopping legacy jellyfin-webdav systemd service..."
    systemctl stop jellyfin-webdav.service
    systemctl disable jellyfin-webdav.service
    rm -f /etc/systemd/system/jellyfin-webdav.service
    systemctl daemon-reload
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
    "${APP_BASE_DIR}/data/rdtclient/downloads" \
    "${APP_BASE_DIR}/data/rclone/cache"

say "Enabling FUSE allow_other support..."
grep -q '^user_allow_other' /etc/fuse.conf 2>/dev/null \
    || echo 'user_allow_other' >> /etc/fuse.conf

say "Setting up shared bind mount for WebDAV mount point..."
if ! mountpoint -q "${APP_BASE_DIR}/mnt/webdav"; then
    mount --bind "${APP_BASE_DIR}/mnt/webdav" "${APP_BASE_DIR}/mnt/webdav"
    mount --make-shared "${APP_BASE_DIR}/mnt/webdav"
fi
FSTAB_LINE="${APP_BASE_DIR}/mnt/webdav ${APP_BASE_DIR}/mnt/webdav none bind,shared 0 0"
grep -qF "$FSTAB_LINE" /etc/fstab || echo "$FSTAB_LINE" >> /etc/fstab

say "Building and starting Docker Compose stack..."
docker compose -f "${REPOSITORY_DIR}/compose.yml" build
docker compose -f "${REPOSITORY_DIR}/compose.yml" up -d

say "Installation complete."
