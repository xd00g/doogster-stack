#!/usr/bin/env bash
#
# Nightly restic backup of the homelab data to Azure Blob.
# Installed at /usr/local/bin/restic-backup.sh, run by restic-backup.timer.
# Config (repo, password file, Azure account, optional Healthchecks URL) is in
# /etc/restic/restic.env — see restic.env.example.
#
set -uo pipefail
set -a; . /etc/restic/restic.env; set +a

RESTIC=/usr/local/bin/restic
STACK=/home/tcc-azure/stack
APPS="linkding lubelogger beszel beszel-agent"
HC="${HEALTHCHECK_URL:-}"

hc()  { [ -n "$HC" ] && curl -fsS -m 10 --retry 3 -o /dev/null "$HC$1" 2>/dev/null || true; }
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
restart_apps() { log "Starting data apps"; docker start $APPS >/dev/null 2>&1 || true; }

hc "/start"
# Safety net: if we die unexpectedly, bring apps back and signal failure.
trap 'restart_apps; hc /fail' EXIT

log "Stopping data apps for a consistent snapshot"
docker stop $APPS >/dev/null 2>&1 || true

log "Backing up personal-apps + stack"
$RESTIC backup /mnt/data/personal-apps "$STACK" --tag scheduled --host tcc-linux-vm1 \
  --exclude '*/homepage/config/logs' --exclude '*/beszel/socket'
rc=$?

restart_apps
trap - EXIT   # apps are back; drop the safety net and handle status explicitly

if [ "$rc" -ne 0 ]; then
  log "Backup FAILED (rc=$rc)"; hc "/fail"; exit "$rc"
fi

log "Pruning (keep 7 daily / 4 weekly / 6 monthly)"
$RESTIC forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
prc=$?

if [ "$prc" -eq 0 ]; then log "Done OK"; hc ""; else log "Prune failed (rc=$prc)"; hc "/fail"; fi
exit "$prc"
