# JellyServarr

A self-hosted media stack powered by Docker Compose. It mounts a remote WebDAV storage with rclone, keeps it in sync, and automatically triggers Jellyfin library scans when new media arrives — all behind a Traefik reverse proxy with automatic HTTPS.

## Services

| Service | Role | URL |
|---|---|---|
| **Jellyfin** | Media server | `jellyfin.yourdomain.tld` |
| **Jellyseerr** | Media request platform | `jellyseerr.yourdomain.tld` |
| **Traefik** | Reverse proxy + TLS | `:80`, `:443` |
| **rclone** | WebDAV mount | internal |
| **media-sync** | Sync sidecar | internal |

## Requirements

- A Linux machine with [Docker](https://github.com/docker/docker-install) and [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) installed
- A WebDAV server (Nextcloud, seedbox, RealDebrid, AllDebrid, etc.)
- A domain pointed at your server (for Traefik HTTPS routing)

---

## Installation

### 1. Download and bootstrap

Run this on your server to clone the repository and generate config files:

```shell
curl -fsSL https://raw.githubusercontent.com/AlexandreVassard/JellyServarr/main/scripts/bootstrap.sh | sudo bash
```

This clones the repo to `/opt/jellyservarr` and creates pre-filled config files ready to edit.

### 2. Configure the environment

```shell
sudo nano /opt/jellyservarr/.env
```

At minimum, set these values:

| Variable | Description | Example |
|---|---|---|
| `TRAEFIK_HOST` | Your domain | `yourdomain.tld` |
| `TLS_CERTIFICATE_MAIL` | Email for Let's Encrypt TLS certificates | `you@example.com` |
| `PUID` / `PGID` | Your host user/group ID (avoids permission issues) | `1000` / `1000` |
| `TZ` | Your timezone | `Europe/Paris` |
| `WEBDAV_PATH` | Path inside your WebDAV remote (leave empty for root) | `media/` |

> **To find your PUID/PGID**, run `id` in your terminal.

`JELLYFIN_TOKEN` can be left empty for now — see [Post-install setup](#post-install-setup) below.

### 3. Configure the rclone WebDAV remote

```shell
sudo nano /opt/jellyservarr/config/rclone.conf
```

Fill in your WebDAV server URL, username, and password. The password must be **obscured** using rclone — run this to get the obscured value:

```shell
docker run --rm rclone/rclone:latest obscure 'your_password'
```

Then paste the output into the `pass =` field in `rclone.conf`.

### 4. Run the install script

```shell
sudo bash /opt/jellyservarr/scripts/install.sh
```

This script handles all low-level setup automatically:

1. **Checks** that `rclone.conf` exists and exits early if not
2. **Creates** all data directories under `/opt/jellyservarr/` (config, cache, mounts, etc.)
3. **Enables FUSE `allow_other`** in `/etc/fuse.conf` so containers can read the WebDAV mount
4. **Sets up a shared bind mount** at `/opt/jellyservarr/mnt/webdav` and persists it in `/etc/fstab` — this makes rclone's FUSE mount visible to Jellyfin and sibling containers even after reboot
5. **Builds and starts** the full Docker Compose stack

Once it completes, all services are running and will **restart automatically on reboot** via Docker's `restart: unless-stopped` policy.

---

## Post-install setup

Configure the two services through their web UI, in this order.

### 1. Jellyfin

Open `https://jellyfin.yourdomain.tld` and complete the setup wizard, then:

**Add the libraries** — *Dashboard → Libraries → Add Media Library*

| Content type | Folder |
|---|---|
| `Movies` | `/medias/movies` |
| `Shows` | `/medias/series` |

Both folders are filled with symlinks by the `media-sync` sidecar. Do not point a library at
`/mnt/webdav` directly — the raw remote has no Jellyfin-compatible naming scheme.

**Generate an API key** — *Dashboard → API Keys → +*

The sidecar needs it to trigger library scans. Paste it into `.env`, then restart the sidecar:

```shell
JELLYFIN_TOKEN=your_token_here
```

```shell
docker compose restart media-sync
```

### 2. Jellyseerr

Open `https://jellyseerr.yourdomain.tld` and pick **Jellyfin** as the media server backend:

| Field | Value |
|---|---|
| Jellyfin URL | `http://jellyfin:8096` |
| Email / Username | *(your Jellyfin admin account)* |
| Password | *(your Jellyfin admin password)* |

Then select the libraries to sync.

> **Note:** Jellyseerr has no download automation behind it in this stack. It works as a
> catalog and a request tracker; approved requests must be fulfilled manually.

---

## Runtime commands

```shell
cd /opt/jellyservarr

# Start or stop the entire stack
docker compose up -d
docker compose down

# Restart a specific service
docker compose restart rclone
docker compose restart media-sync

# Follow logs for a service
docker compose logs -f rclone
docker compose logs -f media-sync
docker compose logs -f jellyfin

# Uninstall (removes mounts, fstab entry, and containers)
sudo bash scripts/uninstall.sh
```

---

## Troubleshooting

**WebDAV mount is not working**
Check your `rclone.conf` credentials, then inspect logs:
```shell
docker compose logs -f rclone
```

**Jellyfin library scan is not triggering**
Make sure `JELLYFIN_TOKEN` is set in `.env` and the sidecar is running:
```shell
docker compose logs -f media-sync
```

**Permission errors on media files**
Set `PUID` and `PGID` in `.env` to match your host user (`id` to check).

**Traefik not issuing certificates**
Make sure your domain points to your server's public IP and that ports 80/443 are open.

---

## Architecture notes

- **FUSE + rshared propagation**: rclone mounts the WebDAV remote inside a container using FUSE. The mount point is bind-mounted with `rshared` propagation so it becomes visible to Jellyfin and other containers — and to the host itself.
- **Shared bind mount in fstab**: The `install.sh` script adds a `bind,shared` entry in `/etc/fstab`. Without this, the propagation mode resets after reboot, breaking the mount.
- **Sidecar restart resilience**: If rclone restarts, the `media-sync` sidecar detects the RC API is unreachable and exits with code 1. Docker then restarts it, which re-establishes the dependency chain correctly.
- **Symlink library layout**: `media-sync` classifies each item at the WebDAV root as a movie or a series and builds symlinks under `mnt/medias/movies` and `mnt/medias/series` (with `Season N/` subfolders). Jellyfin's libraries point at those two folders, never at the raw WebDAV mount.
