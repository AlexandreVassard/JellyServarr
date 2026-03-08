#!/bin/bash
set -e

JELLYFIN_ENABLE_SCAN="${JELLYFIN_ENABLE_SCAN:-true}"
JELLYFIN_SCAN_DELAY="${JELLYFIN_SCAN_DELAY:-10}"
JELLYFIN_URL="${JELLYFIN_URL:-http://localhost:8096}"
JELLYFIN_TOKEN="${JELLYFIN_TOKEN:-}"

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

say "Mounting Jellyfin WebDAV..."
rclone mount jellyfin-webdav:"${WEBDAV_PATH}" /mnt/jellyfin-webdav \
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
    --config /etc/jellyfin-webdav/rclone.conf &

WEBDAV_MOUNT_PID=$!

sleep "${WEBDAV_REFRESH_INITIAL_DELAY}"

say "Starting refresh loop..."

while kill -0 $WEBDAV_MOUNT_PID 2>/dev/null; do
    say "Refreshing WebDAV cache..."
    rclone rc vfs/refresh recursive=true || say "Jellyfin WebDAV refresh failed"

    if [ "$JELLYFIN_ENABLE_SCAN" = true ]; then
        if [ -z "$JELLYFIN_TOKEN" ]; then
            say "Jellyfin scan is enabled but no JELLYFIN_TOKEN provided. Skipping Jellyfin scan."
        else
            say "Waiting ${JELLYFIN_SCAN_DELAY}s before Jellyfin scan..."
            sleep "${JELLYFIN_SCAN_DELAY}"

            say "Triggering Jellyfin library scan..."
            curl -X POST "${JELLYFIN_URL}/Library/Refresh" \
                --header "X-Emby-Token: ${JELLYFIN_TOKEN}" \
                --silent --show-error ||
                say "Failed to trigger Jellyfin library scan"
        fi
    else
        say "Jellyfin scan is disabled. Skipping..."
    fi

    say "Waiting ${WEBDAV_REFRESH_INTERVAL}s before next Jellyfin WebDAV refresh..."
    sleep "${WEBDAV_REFRESH_INTERVAL}"
done

say "Mount process exited. Exiting."
exit 1
