# doogster-stack

Config-as-code for the Doogster Docker host on an Azure Debian 13 VM. Web traffic arrives through Cloudflare Tunnel and reaches Traefik over the external `proxy` network; only SSH is opened directly to the VM.

## What is covered

| Layer | Status | Location |
|---|---|---|
| Compose stack and routing | Versioned | `stack/docker-compose.yml` |
| Homepage and static sites | Versioned | `config/` and `sites/` |
| Docker data-root configuration | Versioned | `system/daemon.json` |
| Fresh-machine bootstrap | Versioned | `bootstrap.sh` |
| Azure Blob data backup job | Versioned and active | `system/restic-*` |
| App data and real `.env` | Encrypted offsite backup | Azure Blob via restic |
| Live secrets | Not committed | VM `.env`, restic password, password manager |
| Cloudflare public hostnames | Dashboard-managed | Cloudflare Zero Trust |

## Current applications

Traefik, cloudflared, Doog's News Feed, Homepage, LubeLogger, Beszel, Portainer, Uptime Kuma, Wallabag, Actual Budget, the main landing page, the Oregon guide, and Whoami.

Persistent application data is stored below `/mnt/data/personal-apps`. Docker's data root is `/mnt/data/docker`.

## Rebuild

1. Provision Debian 13 and mount the data disk at `/mnt/data` using an fstab UUID.
2. Clone this repository and run `./bootstrap.sh` as a normal sudo-capable user.
3. Populate `~/stack/.env` from the password manager.
4. Clone/build the private `doogs-news-feed` repository as `doogs-news-feed:latest`.
5. Follow `RESTORE.md` to restore data and reinstall the backup timer.
6. Run `docker compose --profile monitoring-agent up -d` from `~/stack`.
7. Confirm each Cloudflare public hostname targets `http://traefik:80`.

## Backups

Nightly restic backups are encrypted and stored in Azure Blob. The job snapshots `/mnt/data/personal-apps` and `~/stack`, including the real `.env` inside the encrypted repository. It briefly stops running stateful containers for a consistent filesystem snapshot, then restarts exactly those containers.

Retention is 7 daily, 4 weekly, and 6 monthly snapshots. The repository password is required for every restore and must remain in the password manager. See `RESTORE.md` for validation and disaster-recovery procedures.
