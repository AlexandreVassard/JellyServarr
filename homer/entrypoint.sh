#!/bin/sh
set -e

say() {
    echo >&2 "$(date '+%Y-%m-%d %H:%M:%S') >> $*"
}

TRAEFIK_HOST="${TRAEFIK_HOST:-domain.tld}"
HOMER_LOCAL_IP="${HOMER_LOCAL_IP:-localhost}"

TEMPLATE_CONFIG_PATH="/www/assets/config.yml.dist"
TEMPLATE_CLOUD_PATH="/www/assets/cloud.yml.dist"
CONFIG_PATH="/www/assets/config.yml"
CLOUD_PATH="/www/assets/cloud.yml"

say "Creating \"$CONFIG_PATH\" from template..."
cp "$TEMPLATE_CONFIG_PATH" "$CONFIG_PATH"

say "Creating \"$CLOUD_PATH\" from template..."
cp "$TEMPLATE_CLOUD_PATH" "$CLOUD_PATH"

say "Replacing domain.tld with $TRAEFIK_HOST in $CONFIG_PATH"
sed -i "s/localhost/${HOMER_LOCAL_IP}/g" "$CONFIG_PATH"

say "Replacing localhost with $HOMER_LOCAL_IP in $CLOUD_PATH"
sed -i "s/domain\.tld/${TRAEFIK_HOST}/g" "$CLOUD_PATH"

say "Starting Homer"
. /entrypoint.sh
