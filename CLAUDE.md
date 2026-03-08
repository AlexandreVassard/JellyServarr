# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A Docker Compose stack for self-hosting Jellyfin with satellite services (Radarr, Sonarr, Prowlarr, Jellyseerr, Tautulli, RDTClient, Homer) backed by a WebDAV remote storage mount managed by rclone. There is no application code to build or test — this is purely infrastructure configuration.

## Stack Overview

- **Traefik**: Reverse proxy with Let's Encrypt TLS. All services get `<service>.${TRAEFIK_HOST}` routes.
- **Jellyfin**: Media server. Accesses WebDAV mount at `${APP_BASE_DIR}/mnt/webdav`.
- **Radarr / Sonarr**: Automated movie/TV downloaders. Depend on Prowlarr, RDTClient, and rclone being healthy.
- **Prowlarr**: Indexer manager. Custom indexer definitions in `prowlarr/definitions/` are copied into the container on first run (not overwritten if already present).
- **RDTClient**: Download client (Real-Debrid / AllDebrid torrents). Downloads land in `${APP_BASE_DIR}/data/rdtclient/downloads`, shared as `/downloads` with Radarr/Sonarr.
- **Jellyseerr**: Media request platform. Depends on Radarr and Sonarr being healthy.
- **Tautulli**: Activity monitor. Depends on Jellyfin being healthy.
- **Homer**: Dashboard. Has two views: local (`config.yml`) and cloud (`cloud.yml`). Both are generated from `.dist` templates at container start using `TRAEFIK_HOST` and `HOMER_LOCAL_IP` env vars.
- **rclone**: Docker service that mounts the WebDAV remote at `${APP_BASE_DIR}/mnt/webdav` via FUSE with rshared propagation. Exposes RC API on port 5572 (container-internal only).
- **media-sync** (sidecar): Alpine container that runs `media-sync.sh`. Waits for rclone to be healthy, then loops: refreshes the VFS cache via rclone RC API, syncs symlinks, and triggers Jellyfin library scans.

## Key Files

| File | Purpose |
|------|---------|
| `.env` | Docker Compose environment (copy from `.env.example`) |
| `rclone.conf` | At `${APP_BASE_DIR}/config/rclone.conf` on the host (copy from `rclone.conf.example`) |
| `services/homer/assets/config.yml.dist` | Local dashboard template |
| `services/homer/assets/cloud.yml.dist` | Cloud dashboard template |
| `prowlarr/definitions/ygg-api.yml` | Custom Prowlarr indexer definition for YGG |
| `services/media-sync/media-sync.sh` | Scan loop script (runs inside the media-sync sidecar container) |
| `scripts/install.sh` | Host install script (FUSE setup, bind mount, stack launch) |
| `scripts/uninstall.sh` | Host uninstall script |

## Setup Commands

```bash
# 1. Configure Docker env
cp .env.example .env
# Edit .env: set WEBDAV_PATH, JELLYFIN_TOKEN, and any other values

# 2. Configure rclone WebDAV (obscure password first)
sudo mkdir -p /opt/jellyservarr/config
sudo cp rclone.conf.example /opt/jellyservarr/config/rclone.conf
# Obscure password: docker run --rm rclone/rclone:latest obscure 'your_password'

# 3. Install (sets up FUSE, shared bind mount, fstab, builds and starts the stack)
sudo bash scripts/install.sh
```

## Runtime Commands

```bash
# Start/stop the stack
docker compose up -d
docker compose down

# View logs for a specific service
docker compose logs -f jellyfin
docker compose logs -f rclone
docker compose logs -f media-sync

# Restart a service
docker compose restart rclone
docker compose restart media-sync

# Uninstall
sudo bash scripts/uninstall.sh
```

## Architecture Notes

- **FUSE + rshared propagation**: rclone runs in a Docker container with `cap_add: SYS_ADMIN` and `/dev/fuse`. The WebDAV mount point `${APP_BASE_DIR}/mnt/webdav` is bind-mounted with `propagation: rshared` so the FUSE mount created inside the container propagates to the host and sibling containers.
- **Shared bind mount**: `install.sh` creates a `bind,shared` entry in `/etc/fstab` so the mount point survives reboots with the correct propagation mode. Without this, rclone's FUSE mount stays container-local after reboot.
- **`--allow-other`**: Required so containers running as PUID/PGID can read the mount. Enabled via `user_allow_other` in `/etc/fuse.conf` (added by `install.sh`).
- **`--rc-no-auth`**: RC authentication is disabled. Port 5572 is never exposed to the host (no `ports:` entry), so this is safe within the Docker network.
- **Restart resilience**: If the rclone container restarts, the media-sync sidecar detects RC unreachable (loop condition fails), exits with code 1, and Docker restarts it. `depends_on` only applies at initial startup — this is the correct behavior.
- **rclone remote name**: `jellyfin-webdav` (as configured in `rclone.conf`).
- Homer's entrypoint generates `config.yml` and `cloud.yml` from `.dist` templates each time the container starts — do not edit the non-`.dist` files directly.
- Prowlarr's entrypoint only copies custom definitions if they don't already exist in `/config/Definitions/Custom/`.
- The Jellyfin library scan API is `POST /Library/Refresh` with header `X-Emby-Token: <token>`, which triggers a full library scan.
