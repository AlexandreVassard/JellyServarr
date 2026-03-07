#!/bin/bash
set -e

PLEX_ENABLE_SCAN="${PLEX_ENABLE_SCAN:-true}"
PLEX_SCAN_DELAY="${PLEX_SCAN_DELAY:-10}"
PLEX_URL="${PLEX_URL:-http://localhost:32400}"
PLEX_TOKEN="${PLEX_TOKEN:-}"

WEBDAV_PATH="${WEBDAV_PATH:-}"
WEBDAV_REFRESH_INTERVAL="${WEBDAV_REFRESH_INTERVAL:-60}"
WEBDAV_REFRESH_INITIAL_DELAY="${WEBDAV_REFRESH_INITIAL_DELAY:-15}"

WEBDAV_VFS_CACHE_MODE="${WEBDAV_VFS_CACHE_MODE:-full}"
WEBDAV_VFS_CACHE_MAX_SIZE="${WEBDAV_VFS_CACHE_MAX_SIZE:-10G}"
WEBDAV_VFS_CACHE_MAX_AGE="${WEBDAV_VFS_CACHE_MAX_AGE:-1h}"
WEBDAV_VFS_READ_CHUNK_SIZE="${WEBDAV_VFS_READ_CHUNK_SIZE:-32M}"
WEBDAV_VFS_READ_CHUNK_SIZE_LIMIT="${WEBDAV_VFS_READ_CHUNK_SIZE_LIMIT:-512M}"
WEBDAV_BUFFER_SIZE="${WEBDAV_BUFFER_SIZE:-8M}"
WEBDAV_MULTI_THREAD_STREAMS="${WEBDAV_MULTI_THREAD_STREAMS:-4}"
WEBDAV_CUTOFF_MODE="${WEBDAV_CUTOFF_MODE:-hard}"

say() {
    echo >&2 "$(date '+%Y-%m-%d %H:%M:%S') >> $*"
}

say "Mounting Plex WebDAV..."
rclone mount plex-webdav:"${WEBDAV_PATH}" /mnt/plex-webdav \
    --dir-cache-time "${WEBDAV_REFRESH_INTERVAL}s" \
    --vfs-cache-mode "${WEBDAV_VFS_CACHE_MODE}" \
    --vfs-cache-max-size "${WEBDAV_VFS_CACHE_MAX_SIZE}" \
    --vfs-cache-max-age "${WEBDAV_VFS_CACHE_MAX_AGE}" \
    --vfs-read-chunk-size "${WEBDAV_VFS_READ_CHUNK_SIZE}" \
    --vfs-read-chunk-size-limit "${WEBDAV_VFS_READ_CHUNK_SIZE_LIMIT}" \
    --buffer-size "${WEBDAV_BUFFER_SIZE}" \
    --multi-thread-streams "${WEBDAV_MULTI_THREAD_STREAMS}" \
    --cutoff-mode="${WEBDAV_CUTOFF_MODE}" \
    --network-mode \
    --allow-other \
    --rc \
    --config /etc/plex-webdav/rclone.conf &

WEBDAV_MOUNT_PID=$!

sleep "${WEBDAV_REFRESH_INITIAL_DELAY}"

say "Starting refresh loop..."

while kill -0 $WEBDAV_MOUNT_PID 2>/dev/null; do
    say "Refreshing WebDAV cache..."
    rclone rc vfs/refresh recursive=true || say "Plex WebDAV refresh failed"

    if [ "$PLEX_ENABLE_SCAN" = true ]; then
        if [ -z "$PLEX_TOKEN" ]; then
            say "Plex scan is enabled but no PLEX_TOKEN provided. Skipping Plex scan."
        else
            say "Waiting ${PLEX_SCAN_DELAY}s before Plex scans..."
            sleep "${PLEX_SCAN_DELAY}"

            LIBRARY_IDS=$(curl -s "${PLEX_URL}/library/sections?X-Plex-Token=${PLEX_TOKEN}" | grep -oP 'key="\K[0-9]+')

            if [ -z "$LIBRARY_IDS" ]; then
                say "No Plex libraries found. Skipping..."
            else
                for LIB_ID in $LIBRARY_IDS; do
                    say "Triggering Plex library scan for section ID: ${LIB_ID}..."
                    curl -X POST "${PLEX_URL}/library/sections/${LIB_ID}/refresh" \
                        --header "X-Plex-Token: ${PLEX_TOKEN}" \
                        --silent --show-error ||
                        say "Failed to trigger Plex library scan for section ID: ${LIB_ID}"
                done
            fi
        fi
    else
        say "Plex scan is disabled. Skipping..."
    fi

    say "Waiting ${WEBDAV_REFRESH_INTERVAL}s before next Plex WebDAV refresh..."
    sleep "${WEBDAV_REFRESH_INTERVAL}"
done

say "Mount process exited. Exiting."
exit 1
