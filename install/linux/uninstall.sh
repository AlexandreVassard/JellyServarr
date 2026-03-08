#!/bin/bash
set -e

APP_BASE_DIR="${APP_BASE_DIR:-/opt/jellyfin-servarr}"
SERVICE_DIR="${SERVICE_DIR:-/etc/systemd/system}"
SERVICE_NAME="jellyfin-webdav"
BIN_DIR="${BIN_DIR:-${APP_BASE_DIR}/bin}"
ENV_DIR="${ENV_DIR:-${APP_BASE_DIR}/config}"
SERVICE_FILE="${SERVICE_DIR}/${SERVICE_NAME}.service"
BIN_FILE="${BIN_DIR}/${SERVICE_NAME}.sh"
CONFIG_DIR="${ENV_DIR}"

say() {
    echo >&2 "$(date '+%Y-%m-%d %H:%M:%S') >> $*"
}

if [[ $EUID -ne 0 ]]; then
    say "This script must be run as root. Try again with:"
    say "   sudo $0"
    exit 1
fi

say "Stopping and disabling systemd service..."
systemctl stop "$SERVICE_NAME.service" || say "Service not running."
systemctl disable "$SERVICE_NAME.service" || say "Service not enabled."

say "Removing systemd service file..."
rm -f "$SERVICE_FILE"

say "Reloading systemd daemon..."
systemctl daemon-reload

say "Removing executable script..."
rm -f "$BIN_FILE"

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
