# Restore Runbook — Doogster homelab

How to get data back from the encrypted **restic** backups in Azure Blob. This covers a
single-file recovery, a single-app recovery, and full disaster recovery onto a fresh VM.

> **The repo password is the only key.** It's in your password manager (and on a running VM at
> `/etc/restic/password`). Without it, nothing in the backup can be decrypted — no exceptions.

## Backup facts

- **Repository:** `azure:linuxbackups:tcc-linux-vm1` in storage account `tcc3cxbackups`
- **Auth:** the VM's **system-assigned managed identity** (no keys stored). It needs the
  **Storage Blob Data Contributor** role on the storage account.
- **Network:** the storage account firewall only allows the VM's VNet via a **Microsoft.Storage
  service endpoint** on subnet `snet-westus3-1` (`172.16.0.0/24`). Same-region Azure traffic ignores
  IP allow-rules — a **VNet service endpoint (or private endpoint) is required**, not an IP entry.
- **Contents:** `/mnt/data/personal-apps/*` (Linkding, LubeLogger, Beszel + Homepage config) and
  `~/stack/` (compose **and `.env` with the real secrets**, encrypted inside the backup).
- **Schedule/retention:** nightly 02:30 (+jitter); keep 7 daily / 4 weekly / 6 monthly.

## Prerequisites on the machine doing the restore

restic's **Debian package lacks the Azure backend** — use the official binary:

```bash
curl -fsSL https://github.com/restic/restic/releases/download/v0.18.0/restic_0.18.0_linux_amd64.bz2 -o /tmp/restic.bz2
bunzip2 -f /tmp/restic.bz2 && sudo install -m 0755 /tmp/restic /usr/local/bin/restic
```

Recreate the restic config:

```bash
sudo mkdir -p /etc/restic
printf '%s' 'YOUR-REPO-PASSWORD-FROM-PASSWORD-MANAGER' | sudo tee /etc/restic/password >/dev/null
sudo cp system/restic.env.example /etc/restic/restic.env   # edit if names differ
sudo chmod 600 /etc/restic/password /etc/restic/restic.env
```

Load it into your shell for the commands below:

```bash
set -a; . /etc/restic/restic.env; set +a
```

## Inspect what's there

```bash
sudo -E restic snapshots            # list all snapshots
sudo -E restic ls latest            # browse files in the newest snapshot
sudo -E restic stats latest         # size of latest snapshot
sudo -E restic check                # verify repository integrity
```

## Restore a single file

```bash
sudo -E restic restore latest --target /tmp/recover --include /home/tcc-azure/stack/.env
# -> /tmp/recover/home/tcc-azure/stack/.env
```

## Restore one app's data (e.g. Linkding)

```bash
docker stop linkding
sudo -E restic restore latest --target / --include /mnt/data/personal-apps/linkding
docker start linkding
```

`--target /` writes files back to their original absolute paths. Stop the app first so nothing is
mid-write during the restore.

## Full disaster recovery (fresh VM)

1. **Provision** a Debian 13 VM; attach + mount the data disk at `/mnt/data` (ext4, fstab by UUID, `nofail`).
2. **Azure access for the new VM:**
   - Enable the VM's system-assigned managed identity.
   - Grant it **Storage Blob Data Contributor** on `tcc3cxbackups`.
   - On the storage account networking, add the new VM's **subnet** as a virtual-network rule
     (**Microsoft.Storage service endpoint**). *(An IP allow-entry will NOT work for same-region traffic.)*
3. **Install official restic + config** (see Prerequisites above).
4. **Rebuild the stack structure:** clone this repo and run `./bootstrap.sh` (installs Docker, creates
   dirs + the `proxy` network, drops in the compose file + Homepage config).
5. **Build the app image:** `git clone https://github.com/aamostcc/doogs-news-feed.git ~/news-feed &&
   docker build -t doogs-news-feed:latest ~/news-feed`.
6. **Restore the data (and secrets):**
   ```bash
   set -a; . /etc/restic/restic.env; set +a
   sudo -E restic restore latest --target / \
     --include /mnt/data/personal-apps \
     --include /home/tcc-azure/stack
   ```
   This brings back all app data **and** `~/stack/.env` with the real tokens — so you don't have to
   re-enter secrets.
7. **(Optional) reinstall the backup job** so the new VM keeps backing up:
   ```bash
   sudo cp system/restic-backup.sh /usr/local/bin/ && sudo chmod 700 /usr/local/bin/restic-backup.sh
   sudo cp system/restic-backup.service system/restic-backup.timer /etc/systemd/system/
   sudo systemctl daemon-reload && sudo systemctl enable --now restic-backup.timer
   ```
8. **Start the stack:** `cd ~/stack && docker compose up -d`
   (host metrics agent: `docker compose --profile monitoring-agent up -d`).
9. **Cloudflare:** if it's a new tunnel, re-add the public hostnames (`news`, `links`, `cars`,
   `status`, `home`, `traffic`) → `http://traefik:80`.

## Sanity check after any restore

```bash
sudo -E restic check
docker compose -f ~/stack/docker-compose.yml ps
```
