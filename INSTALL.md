# Post-Stack Configuration

Once the Docker stack is running, configure each service through its web UI in the order below.

---

## Table of Contents

1. [Jellyfin](#1-jellyfin)
2. [Jellyseerr](#2-jellyseerr)

---

## 1. Jellyfin

> Complete the initial setup wizard before configuring the libraries below.

### Libraries

**Dashboard → Libraries → Add Media Library**

| Content type | Folder |
|---|---|
| `Movies` | `/medias/movies` |
| `Shows` | `/medias/series` |

Both folders are populated with symlinks by the `media-sync` sidecar. Do not point a library
at `/mnt/webdav` directly — the raw remote has no Jellyfin-compatible naming scheme.

### API key

The `media-sync` sidecar needs an API key to trigger library scans.

**Dashboard → API Keys → +**

Copy the token into `JELLYFIN_TOKEN` in `.env`, then restart the sidecar:

```shell
docker compose restart media-sync
```

---

## 2. Jellyseerr

> Complete the initial login setup before configuring the settings below.

### Media Server

At first launch, choose **Jellyfin** as the media server backend.

| Field | Value |
|---|---|
| Jellyfin URL | `http://jellyfin:8096` |
| Email / Username | *(your Jellyfin admin account)* |
| Password | *(your Jellyfin admin password)* |

Then select the **Films** and **Séries** libraries to sync.

> **Note:** with Radarr and Sonarr removed from the stack, Jellyseerr has no download
> automation to forward requests to. It works as a catalog and a request/wishlist tracker;
> approved requests must be fulfilled manually.
