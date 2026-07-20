# Restore Runbook - Doogster homelab

The encrypted restic repository is `azure:linuxbackups:tcc-linux-vm1` in Azure Storage account `tcc3cxbackups`.

## Requirements

- Restic repository password from the password manager; it cannot be recovered.
- System-assigned managed identity with `Storage Blob Data Contributor` on the storage account.
- Network access through the Azure VNet storage service endpoint.
- Official restic 0.18.0 or newer; Debian's package lacks the Azure backend.

```bash
curl -fsSL https://github.com/restic/restic/releases/download/v0.18.0/restic_0.18.0_linux_amd64.bz2 -o /tmp/restic.bz2
bunzip2 -f /tmp/restic.bz2
sudo install -m 0755 /tmp/restic /usr/local/bin/restic
sudo install -d -m 700 /etc/restic /var/cache/restic
printf '%s\n' 'PASSWORD-FROM-PASSWORD-MANAGER' | sudo tee /etc/restic/password >/dev/null
sudo cp system/restic.env.example /etc/restic/restic.env
sudo chmod 600 /etc/restic/password /etc/restic/restic.env
```

## Inspect and validate

```bash
sudo bash -c 'set -a; . /etc/restic/restic.env; set +a; restic snapshots'
sudo bash -c 'set -a; . /etc/restic/restic.env; set +a; restic check'
```

## Restore one file

```bash
sudo bash -c 'set -a; . /etc/restic/restic.env; set +a; restic restore latest --target /tmp/recover --include /home/tcc-azure/stack/.env'
```

## Restore one application

Stop its container, restore its directory, then restart it. Example:

```bash
docker stop wallabag
sudo bash -c 'set -a; . /etc/restic/restic.env; set +a; restic restore latest --target / --include /mnt/data/personal-apps/wallabag'
docker start wallabag
```

## Full disaster recovery

1. Provision Debian 13, attach the data disk, and mount it at `/mnt/data`.
2. Enable managed identity and grant Azure Blob data access.
3. Clone this repository and run `./bootstrap.sh`.
4. Install official restic and its configuration as shown above.
5. Restore the encrypted stack and application data:

   ```bash
   sudo bash -c 'set -a; . /etc/restic/restic.env; set +a; restic restore latest --target / --include /mnt/data/personal-apps --include /home/tcc-azure/stack'
   ```

6. Clone and build `doogs-news-feed` if its image is unavailable.
7. Install the backup job:

   ```bash
   sudo cp system/restic-backup.sh /usr/local/bin/restic-backup.sh
   sudo chmod 700 /usr/local/bin/restic-backup.sh
   sudo cp system/restic-backup.service system/restic-backup.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now restic-backup.timer
   ```

8. Start the stack with `docker compose --profile monitoring-agent up -d`.
9. Recreate or verify Cloudflare Tunnel hostnames.

## Post-restore verification

```bash
sudo bash -c 'set -a; . /etc/restic/restic.env; set +a; restic check'
docker compose -f ~/stack/docker-compose.yml --profile monitoring-agent ps
```
## Restore Actual CLI access

The Actual CLI image and wrapper are restored from this repository, but its credentials are intentionally not. After a rebuild, run `sudo actual-cli-configure` on the VM to recreate `/etc/actual-cli/actual.env`, then verify with `actual-cli budgets list`. Never commit that credential file.
