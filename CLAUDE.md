# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A Docker Compose stack for self-hosting Jellyfin, backed by a WebDAV remote storage mount managed by rclone. There is no application code to build or test — this is purely infrastructure configuration.

## Stack Overview

- **Traefik**: Reverse proxy with Let's Encrypt TLS. All services get `<service>.${TRAEFIK_HOST}` routes.
- **Jellyfin**: Media server. Reads the symlink libraries at `${APP_BASE_DIR}/mnt/medias` (mounted as `/medias`) and the raw WebDAV mount at `${APP_BASE_DIR}/mnt/webdav`.
- **Jellyseerr**: Media request platform, backed by Jellyfin. Depends on Jellyfin being healthy. With no *arr services in the stack, it acts as a catalog / request tracker only — nothing fulfills requests automatically.
- **rclone**: Docker service that mounts the WebDAV remote at `${APP_BASE_DIR}/mnt/webdav` via FUSE with rshared propagation. Exposes RC API on port 5572 (container-internal only).
- **media-sync** (sidecar): Alpine container that runs `media-sync.sh`. Waits for rclone to be healthy, then loops: refreshes the VFS cache via rclone RC API, syncs symlinks, and asks Jellyfin for a scan when — and only when — the symlinks changed.

All five services sit on the project's default Compose network, where the service name is the DNS alias (`http://jellyfin:8096`, `http://rclone:5572`).

## Key Files

| File | Purpose |
|------|---------|
| `.env` | Docker Compose environment (copy from `.env.example`) |
| `rclone.conf` | At `${APP_BASE_DIR}/config/rclone.conf` on the host (copy from `rclone.conf.example`) |
| `services/media-sync/media-sync.sh` | Scan loop script (runs inside the media-sync sidecar container) |
| `scripts/install.sh` | Host install script (FUSE setup, bind mount, stack launch) |
| `scripts/update.sh` | Pull latest repo + images and recreate containers |
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
- **Published ports**: only Traefik (80/443, on `${TRAEFIK_BIND_IP}` — set it to a single host address when another service holds those ports on a different interface, since binding `0.0.0.0` fails then) and Jellyfin (8096 for LAN clients, 7359/udp for auto-discovery) are published. Everything else is reached over HTTPS through Traefik. The Traefik dashboard is off — `--api.insecure` serves it unauthenticated, so re-enabling it means putting it behind a router with basic-auth.
- **`environment:` over `env_file:`**: each service declares only the variables it needs. Only media-sync uses `env_file: .env`, since it reads most of the file.
- **Restart resilience**: If the rclone container restarts, the media-sync sidecar detects RC unreachable (loop condition fails), exits with code 1, and Docker restarts it. `depends_on` only applies at initial startup — this is the correct behavior.
- **rclone remote name**: `jellyfin-webdav` (as configured in `rclone.conf`).
- **Symlink libraries**: `media-sync.sh` classifies each entry at the WebDAV root as a movie or a series and links it into `mnt/medias/movies` or `mnt/medias/series/<Show>/Season N/`. Jellyfin's libraries point at those folders, not at the raw mount.
- The Jellyfin library scan API is `POST /Library/Refresh` with header `X-Emby-Token: <token>`, which triggers a full library scan. That scan is expensive over the WebDAV mount, so `media-sync.sh` only fires it when a symlink was actually added or removed. `sync_symlinks` records that through the `/tmp/media-sync-changed` marker file — a plain variable would not survive the `while read` subshells. The marker is cleared only once Jellyfin accepts the request, so a failed scan is retried next cycle.
- **Video extensions** live in the single `VIDEO_EXTENSIONS` array in `media-sync.sh`; the `find` expression and the filename regex are both derived from it.
