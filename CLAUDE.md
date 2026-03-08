# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A Docker Compose stack for self-hosting Jellyfin with satellite services (Radarr, Sonarr, Prowlarr, Jellyseerr, Tautulli, RDTClient, Homer) backed by a WebDAV remote storage mount managed by rclone. There is no application code to build or test — this is purely infrastructure configuration.

## Stack Overview

- **Traefik**: Reverse proxy with Let's Encrypt TLS. All services get `<service>.${TRAEFIK_HOST}` routes.
- **Jellyfin**: Media server. Accesses WebDAV mount at `/mnt/jellyfin-webdav`.
- **Radarr / Sonarr**: Automated movie/TV downloaders. Depend on Prowlarr and RDTClient being healthy.
- **Prowlarr**: Indexer manager. Custom indexer definitions in `prowlarr/definitions/` are copied into the container on first run (not overwritten if already present).
- **RDTClient**: Download client (Real-Debrid / AllDebrid torrents). Downloads land in `./data/rdtclient/downloads`, shared as `/downloads` with Radarr/Sonarr.
- **Jellyseerr**: Media request platform. Depends on Radarr and Sonarr being healthy.
- **Tautulli**: Activity monitor. Depends on Jellyfin being healthy.
- **Homer**: Dashboard. Has two views: local (`config.yml`) and cloud (`cloud.yml`). Both are generated from `.dist` templates at container start using `TRAEFIK_HOST` and `HOMER_LOCAL_IP` env vars.
- **jellyfin-webdav** (systemd): Runs on the host (not in Docker). Uses rclone to mount the WebDAV remote at `/mnt/jellyfin-webdav`, then loops: refreshes the VFS cache and triggers Jellyfin library scans.

## Key Files

| File | Purpose |
|------|---------|
| `.env` | Docker Compose environment (copy from `.env.example`) |
| `rclone.conf` | At `/etc/jellyfin-webdav/rclone.conf` on the host (copy from `rclone.conf.example`) |
| `/etc/jellyfin-webdav/.env` | Host-side overrides for jellyfin-webdav service (copy from `.jellyfin-webdav.env.example`) |
| `homer/assets/config.yml.dist` | Local dashboard template |
| `homer/assets/cloud.yml.dist` | Cloud dashboard template |
| `prowlarr/definitions/ygg-api.yml` | Custom Prowlarr indexer definition for YGG |
| `install/linux/scripts/jellyfin-webdav.sh` | Main script for the WebDAV mount + Jellyfin scan loop |
| `install/linux/services/jellyfin-webdav.service` | Systemd unit for the above |

## Setup Commands

```bash
# 1. Configure Docker env
cp .env.example .env

# 2. Configure rclone WebDAV (obscure password first)
sudo mkdir -p /etc/jellyfin-webdav
sudo cp rclone.conf.example /etc/jellyfin-webdav/rclone.conf
# Obscure password: docker run --rm rclone/rclone:latest obscure 'your_password'

# 3. (Optional) Override jellyfin-webdav service defaults
sudo cp .jellyfin-webdav.env.example /etc/jellyfin-webdav/.env

# 4. Install systemd service (requires rclone on host)
sudo bash install/linux/install.sh

# 5. Start Docker stack
docker compose up -d
```

## Runtime Commands

```bash
# Start/stop the stack
docker compose up -d
docker compose down

# View logs for a specific service
docker compose logs -f jellyfin
docker compose logs -f jellyfin-webdav  # (not applicable — use journalctl)

# WebDAV service logs
journalctl -u jellyfin-webdav -f

# Restart WebDAV service
sudo systemctl restart jellyfin-webdav

# Uninstall systemd service
sudo bash install/linux/uninstall.sh
```

## Architecture Notes

- The WebDAV mount (`/mnt/jellyfin-webdav`) is shared between the host (via systemd) and Docker containers (Jellyfin, Radarr, Sonarr, RDTClient) via a bind mount. The host must mount it before Docker containers start.
- The `jellyfin-webdav` systemd service loads `/etc/jellyfin-webdav/.env.default` first, then `/etc/jellyfin-webdav/.env` as an override (the `-` prefix in the unit file makes the override optional).
- Homer's entrypoint generates `config.yml` and `cloud.yml` from `.dist` templates each time the container starts — do not edit the non-`.dist` files directly.
- Prowlarr's entrypoint only copies custom definitions if they don't already exist in `/config/Definitions/Custom/`.
- The Jellyfin library scan API is `POST /Library/Refresh` with header `X-Emby-Token: <token>`, which triggers a full library scan.
