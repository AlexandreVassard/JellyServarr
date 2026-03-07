# Plex Servarr WebDAV

This project provides a complete stack to host a Plex server and its satellite services (Radarr, Sonarr, Prowlarr, Overseerr, Tautulli, Homer, RdtClient), with automatic management of remote WebDAV storage—all orchestrated with Docker Compose and Traefik.

![dashboard screenshot](docs/images/dashboard.png)

## Key Features

- Automatic mounting of WebDAV storage (via rclone)
- Regular refresh of WebDAV content
- Automatic triggering of Plex library scans when new media is added
- Complete media services stack (Plex, Radarr, Sonarr, etc.)

## Requirements

- Linux system (with [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) and [Docker](https://github.com/docker/docker-install) installed)
- Access to a WebDAV server (Nextcloud, Seedbox, RealDebrid, AllDebrid, etc.)
- A Plex account (https://www.plex.tv/)
- A domain or subdomain for Traefik access (optional)

## Linux installation

### 1. Clone the repository

You will need all the files of this repository.

This will create automatically a `plex-servarr-webdav` folder.

```shell
git clone https://gitlab.com/alexandrevassard1/plex-servarr-webdav.git
cd plex-servarr-webdav
```

### 2. Configure environment/config files

Copy and fill Docker environment file :

```shell
cp .env.example .env
```

Create service needed folder :

```shell
sudo mkdir -p /etc/plex-webdav
```

Copy and fill Rclone WebDAV config file :

```shell
sudo cp rclone.conf.example /etc/plex-webdav/rclone.conf
sudo nano /etc/plex-webdav/rclone.conf
```

Plex WebDAV service will use `/etc/plex-webdav/.env.default` by default.

If you need to override some values, create a local env file :

```shell
sudo nano /etc/plex-webdav/.env
```

### 3. Run install script

```shell
sudo bash install/linux/install.sh
```

### 4. Start Plex Servarr WebDAV

```shell
docker compose up -d
```

## Troubleshooting

- **WebDAV mount not working**: Check `rclone.conf` configuration and logs for the `plex-webdav` service.
- **Plex scan not triggered**: Make sure `PLEX_TOKEN` is correctly set in `/etc/plex-webdav/.env`.
- **Permission issues**: Adjust `PUID` / `PGID` in `.env` to match your user.

## Useful Links

- [Plex Documentation](https://support.plex.tv/)
