#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR=/etc/actual-cli
CONFIG_FILE="$CONFIG_DIR/actual.env"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this configuration helper with sudo." >&2
  exit 1
fi

read -r -p "Actual budget Sync ID: " sync_id
if [ -z "$sync_id" ]; then
  echo "Sync ID cannot be empty." >&2
  exit 1
fi

printf 'Authentication method: [P]assword or [T]oken (default: password): '
read -r auth_type
case "$auth_type" in
  ""|p|P|password|Password)
    read -r -s -p "Actual server password: " credential
    printf '\n'
    credential_name=ACTUAL_PASSWORD
    ;;
  t|T|token|Token)
    read -r -s -p "Actual session token: " credential
    printf '\n'
    credential_name=ACTUAL_SESSION_TOKEN
    ;;
  *)
    echo "Enter P for password or T for token." >&2
    exit 1
    ;;
esac

if [ -z "$credential" ]; then
  echo "Credential cannot be empty." >&2
  exit 1
fi

read -r -p "Does this budget use end-to-end encryption? [y/N]: " encrypted
if [[ "$encrypted" =~ ^[Yy]$ ]]; then
  read -r -s -p "Budget encryption password: " encryption_password
  printf '\n'
  if [ -z "$encryption_password" ]; then
    echo "Encryption password cannot be empty." >&2
    exit 1
  fi
else
  encryption_password=
fi

if [[ "$sync_id" == *$'\n'* || "$credential" == *$'\n'* || "$encryption_password" == *$'\n'* ]]; then
  echo "Values cannot contain newlines." >&2
  exit 1
fi

umask 077
install -d -o root -g docker -m 0750 "$CONFIG_DIR"
temp_file=$(mktemp "$CONFIG_DIR/actual.env.XXXXXX")
trap 'rm -f "$temp_file"' EXIT
printf 'ACTUAL_SYNC_ID=%s\n%s=%s\n' "$sync_id" "$credential_name" "$credential" > "$temp_file"
if [ -n "$encryption_password" ]; then
  printf 'ACTUAL_ENCRYPTION_PASSWORD=%s\n' "$encryption_password" >> "$temp_file"
fi
chown root:docker "$temp_file"
chmod 0640 "$temp_file"
mv "$temp_file" "$CONFIG_FILE"
trap - EXIT

echo
echo "SUCCESS: Actual CLI credentials are configured."
echo "Saved securely at $CONFIG_FILE for root and the Docker admin group."