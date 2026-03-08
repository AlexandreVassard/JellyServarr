# Post-Stack Configuration

Once the Docker stack is running, configure each service through its web UI in the order below.

---

## Table of Contents

1. [RDTClient](#1-rdtclient)
2. [Radarr](#2-radarr)
3. [Sonarr](#3-sonarr)
4. [Prowlarr](#4-prowlarr)

---

## 1. RDTClient

> Complete the initial login and provider setup before configuring the settings below.

### Download Client

**Settings → Download Client**

| Field | Value |
|---|---|
| Download client | `Symlink Downloader` |
| Download path | `/downloads` |
| Mapped path | `/downloads` |
| Rclone mount path | `/mnt/webdav` |

### Post-Download Behavior

**Settings → qBittorrent / \*darr**

| Field | Value |
|---|---|
| Post Download Action | `Remove Torrent From Client` |

---

## 2. Radarr

> Complete the initial login setup before configuring the settings below.

### Root Folder

**Settings → Media Management → Add Root Folder**

```
/downloads
```

### Download Client

**Settings → Download Clients → + → qBittorrent**

| Field | Value |
|---|---|
| Name | `rdtclient` |
| Host | `rdtclient` |
| Port | `6500` |
| Username | *(your RDTClient username)* |
| Password | *(your RDTClient password)* |
| Category | `radarr` |

---

## 3. Sonarr

> Complete the initial login setup before configuring the settings below.

### Root Folder

**Settings → Media Management → Add Root Folder**

```
/downloads
```

### Download Client

**Settings → Download Clients → + → qBittorrent**

| Field | Value |
|---|---|
| Name | `rdtclient` |
| Host | `rdtclient` |
| Port | `6500` |
| Username | *(your RDTClient username)* |
| Password | *(your RDTClient password)* |
| Category | `sonarr` |

---

## 4. Prowlarr

> Complete the initial login setup and add your indexers.

### Connect Radarr

**Settings → Apps → + → Radarr**

| Field | Value |
|---|---|
| Prowlarr Server | `http://prowlarr:9696` |
| Radarr Server | `http://radarr:7878` |
| API Key | *(Radarr → Settings → General → API Key)* |

### Connect Sonarr

**Settings → Apps → + → Sonarr**

| Field | Value |
|---|---|
| Prowlarr Server | `http://prowlarr:9696` |
| Sonarr Server | `http://sonarr:8989` |
| API Key | *(Sonarr → Settings → General → API Key)* |
