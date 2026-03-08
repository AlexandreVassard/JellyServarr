#!/bin/bash
set -e

APP_BASE_DIR="${APP_BASE_DIR:-/opt/jellyfin-servarr}"
WORKING_DIR="${WORKING_DIR:-$(readlink -f "$(dirname "$0")")}"
REPOSITORY_DIR="${REPOSITORY_DIR:-$(readlink -f "$WORKING_DIR/..")}"
CONFIG_DIR="${APP_BASE_DIR}/config"

say() {
    echo >&2 "$(date '+%Y-%m-%d %H:%M:%S') >> $*"
}

if [[ $EUID -ne 0 ]]; then
    say "This script must be run as root. Try again with:"
    say "   sudo $0"
    exit 1
fi

say "Stopping Docker Compose stack..."
docker compose -f "${REPOSITORY_DIR}/compose.yml" down || say "Stack not running."

say "Unmounting shared WebDAV mount point..."
umount -l "${APP_BASE_DIR}/mnt/webdav" 2>/dev/null || say "Mount not active."
FSTAB_LINE="${APP_BASE_DIR}/mnt/webdav ${APP_BASE_DIR}/mnt/webdav none bind,shared 0 0"
grep -vF "$FSTAB_LINE" /etc/fstab > /tmp/fstab.tmp && mv /tmp/fstab.tmp /etc/fstab

if [ -d "$CONFIG_DIR" ]; then
    read -p "Do you also want to delete the config directory at $CONFIG_DIR? [y/N]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        say "Removing configuration directory..."
        rm -rf "$CONFIG_DIR"
    else
        say "Configuration directory preserved."
    fi
else
    say "Configuration directory not found, nothing to remove."
fi

echo ""
say "Uninstallation complete."
