# doogster-stack

Config-as-code for the Doogster homelab — the Docker stack running on an Azure Debian 13
VM, reached entirely through a Cloudflare Tunnel (no inbound ports except SSH).

This repo lets you **rebuild the stack's structure** on a fresh box and gives you version
history for every config change. It is **not** a data backup (see below).

## What this does and does NOT do

| Layer | Covered here? | Notes |
|-------|---------------|-------|
| Stack definition (compose, configs, network, dirs) | ✅ yes | `docker-compose.yml`, Homepage config, `daemon.json`, `bootstrap.sh` |
| One-command rebuild on a fresh VM | ✅ yes | `bootstrap.sh` |
| **App data** (Linkding bookmarks, LubeLogger history, Beszel metrics) | ❌ no | Needs a real backup of `/mnt/data/personal-apps/*` (restic/borg → offsite) |
| **Secrets** (Cloudflare/Beszel tokens) | ❌ no | Only `.env.example` is committed; real `.env` is gitignored — keep values in a password manager |
| Cloudflare Tunnel routes | ❌ no | Managed in the Cloudflare dashboard; they survive rebuilds as long as you reuse the tunnel token |

## Layout

```
doogster-stack/
├── bootstrap.sh            # rebuild the stack on a fresh Debian 13 VM
├── stack/
│   ├── docker-compose.yml  # traefik, cloudflared, whoami, news-feed, linkding,
│   │                       # lubelogger, beszel, beszel-agent, homepage
│   └── .env.example        # secret keys with placeholder values (copy to ~/stack/.env)
├── config/
│   └── homepage/           # -> /mnt/data/personal-apps/homepage/config
│       ├── settings.yaml   # title, theme, layout
│       ├── services.yaml   # Homelab + Personal Apps (with live siteMonitor checks)
│       ├── bookmarks.yaml  # Dev & MSP + Ground Control
│       ├── widgets.yaml    # greeting, Las Vegas weather, clock, search
│       └── custom.css      # xD00g cosmic starfield theme
└── system/
    └── daemon.json         # -> /etc/docker/daemon.json (Docker data-root on /mnt/data)
```

## Infrastructure assumptions

- **OS:** Debian 13 (Trixie) on an Azure VM; public IP with NSG locked to the home IP, SSH key-only.
- **Data disk:** a separate disk (e.g. `sda1`, ext4) mounted at `/mnt/data` via `/etc/fstab` by UUID
  with `nofail`. `bootstrap.sh` refuses to run if `/mnt/data` isn't a mountpoint.
- **No inbound ports** except SSH — all web traffic arrives via `cloudflared` (Cloudflare Tunnel),
  which reaches Traefik over the shared external Docker network `proxy`.

## Routing pattern (per app)

- **Traefik label block:** `enable=true`, `rule=Host(`sub.doogster.com`)`, `entrypoints=web`,
  and an explicit `loadbalancer.server.port` when the port isn't obvious.
- **Cloudflare Tunnel public hostname:** `sub.doogster.com` → `http://traefik:80`.

Current subdomains: `traffic` (whoami test), `news`, `links`, `cars`, `status`, `home`.

## Rebuild on a fresh VM

1. Provision the VM, attach + mount the data disk at `/mnt/data` (ext4, fstab by UUID, `nofail`).
2. Clone this repo and run the bootstrap:
   ```bash
   git clone <this repo> ~/doogster-stack && cd ~/doogster-stack
   ./bootstrap.sh
   ```
3. Fill in `~/stack/.env` with the real tokens (from your password manager).
4. Build the `news-feed` image (separate app repo — needs a Dockerfile):
   ```bash
   git clone https://github.com/aamostcc/doogs-news-feed.git ~/news-feed
   docker build -t doogs-news-feed:latest ~/news-feed
   ```
5. Start it: `cd ~/stack && docker compose up -d`
   (host metrics agent: `docker compose --profile monitoring-agent up -d`)
6. In the Cloudflare Tunnel dashboard, confirm each public hostname points at `http://traefik:80`.

## Next layer: real data backup (TODO)

The important safety net still to add: a scheduled, encrypted, versioned backup of
`/mnt/data/personal-apps/*` to an offsite target (Backblaze B2 / Azure Blob) using
**restic** or **borg**, with a documented restore test.
