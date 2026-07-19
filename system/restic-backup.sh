#!/usr/bin/env bash
# Consistent nightly backup of stateful homelab data to Azure Blob.
set -uo pipefail
set -a; . /etc/restic/restic.env; set +a

RESTIC=/usr/local/bin/restic
STACK=/home/tcc-azure/stack
HC="${HEALTHCHECK_URL:-}"
# These services write persistent databases/state under /mnt/data/personal-apps.
STATEFUL_APPS=(lubelogger beszel beszel-agent wallabag actual uptime-kuma portainer)
RUNNING_APPS=()

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
hc()  { [ -n "$HC" ] && curl -fsS -m 10 --retry 3 -o /dev/null "$HC$1" 2>/dev/null || true; }

restart_apps() {
  if [ "${#RUNNING_APPS[@]}" -gt 0 ]; then
    log "Restarting: ${RUNNING_APPS[*]}"
    docker start "${RUNNING_APPS[@]}" >/dev/null 2>&1 || true
  fi
}

# Prevent a manual run from overlapping the systemd timer.
exec 9>/run/lock/restic-backup.lock
if ! flock -n 9; then
  log "Another backup is already running; exiting"
  exit 75
fi

for app in "${STATEFUL_APPS[@]}"; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$app" 2>/dev/null || true)" = "true" ]; then
    RUNNING_APPS+=("$app")
  fi
done

hc "/start"
trap 'restart_apps; hc /fail' EXIT

if [ "${#RUNNING_APPS[@]}" -gt 0 ]; then
  log "Stopping for consistent snapshot: ${RUNNING_APPS[*]}"
  docker stop --time 30 "${RUNNING_APPS[@]}" >/dev/null
fi

log "Backing up /mnt/data/personal-apps and $STACK"
"$RESTIC" backup /mnt/data/personal-apps "$STACK" \
  --tag scheduled --host tcc-linux-vm1 \
  --exclude '*/homepage/config/logs' \
  --exclude '*/beszel/socket'
rc=$?

restart_apps
trap - EXIT

if [ "$rc" -ne 0 ]; then
  log "Backup FAILED (rc=$rc)"; hc "/fail"; exit "$rc"
fi

log "Applying retention: 7 daily / 4 weekly / 6 monthly"
"$RESTIC" forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
prc=$?

if [ "$prc" -eq 0 ]; then
  log "Backup and prune completed successfully"; hc ""
else
  log "Prune failed (rc=$prc)"; hc "/fail"
fi
exit "$prc"
