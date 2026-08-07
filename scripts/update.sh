#!/bin/bash
set -e

WORKING_DIR="${WORKING_DIR:-$(readlink -f "$(dirname "$0")")}"
REPOSITORY_DIR="${REPOSITORY_DIR:-$(readlink -f "$WORKING_DIR/..")}"

say() {
    echo >&2 "$(date '+%Y-%m-%d %H:%M:%S') >> $*"
}

say "Pulling latest repository changes..."
git -C "${REPOSITORY_DIR}" pull --ff-only

say "Pulling latest Docker images..."
docker compose -f "${REPOSITORY_DIR}/compose.yml" pull

say "Recreating containers with updated images..."
docker compose -f "${REPOSITORY_DIR}/compose.yml" up -d --remove-orphans

say "Removing unused Docker images..."
docker image prune -f

say "Update complete."
