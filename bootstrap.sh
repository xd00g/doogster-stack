#!/usr/bin/env bash
# Bootstrap the Doogster stack structure on a fresh Debian 13 VM.
# This installs configuration, not app data or secrets. See RESTORE.md.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$HOME/stack"
DATA=/mnt/data
HP_CONFIG="$DATA/personal-apps/homepage/config"

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf '!! %s\n' "$*"; }

[ "$(id -u)" = 0 ] && { warn "Run as a normal sudo-capable user, not root."; exit 1; }
mountpoint -q "$DATA" || { warn "$DATA is not a mountpoint; mount the data disk first."; exit 1; }

if ! command -v docker >/dev/null 2>&1; then
  say "Installing Docker"
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  warn "Log out/in after completion so Docker group membership takes effect."
else
  say "Docker present: $(docker --version)"
fi

say "Configuring Docker data-root"
sudo mkdir -p /etc/docker "$DATA/docker"
sudo cp "$REPO_DIR/system/daemon.json" /etc/docker/daemon.json
sudo systemctl restart docker

say "Creating persistent application directories"
sudo mkdir -p \
  "$HP_CONFIG" \
  "$DATA/personal-apps/lubelogger/data" \
  "$DATA/personal-apps/lubelogger/keys" \
  "$DATA/personal-apps/beszel/data" \
  "$DATA/personal-apps/beszel/socket" \
  "$DATA/personal-apps/beszel/agent" \
  "$DATA/personal-apps/wallabag/data" \
  "$DATA/personal-apps/wallabag/images" \
  "$DATA/personal-apps/portainer" \
  "$DATA/personal-apps/uptime-kuma" \
  "$DATA/personal-apps/actual" \
  "$DATA/personal-apps/landing" \
  "$DATA/personal-apps/oregon"
sudo chown -R "$USER":"$USER" "$DATA/personal-apps"

say "Deploying Compose, Homepage, and static sites"
mkdir -p "$STACK_DIR"
cp "$REPO_DIR/stack/docker-compose.yml" "$STACK_DIR/docker-compose.yml"
cp "$REPO_DIR"/config/homepage/*.yaml "$HP_CONFIG"/
cp "$REPO_DIR"/config/homepage/*.css "$HP_CONFIG"/
cp -a "$REPO_DIR/sites/landing/." "$DATA/personal-apps/landing/"
cp -a "$REPO_DIR/sites/oregon/." "$DATA/personal-apps/oregon/"

if [ ! -f "$STACK_DIR/.env" ]; then
  cp "$REPO_DIR/stack/.env.example" "$STACK_DIR/.env"
  warn "Created $STACK_DIR/.env from placeholders; insert real secrets before startup."
fi

say "Ensuring shared proxy network exists"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy

say "Checking News Feed image"
if docker image inspect doogs-news-feed:latest >/dev/null 2>&1; then
  echo "doogs-news-feed:latest already present"
elif [ -d "$HOME/news-feed" ]; then
  docker build -t doogs-news-feed:latest "$HOME/news-feed"
else
  warn "Clone the private doogs-news-feed repository to ~/news-feed and build its Dockerfile."
fi

cd "$STACK_DIR"
if grep -q 'replace-with' .env 2>/dev/null; then
  warn "Edit $STACK_DIR/.env, then run: docker compose --profile monitoring-agent up -d"
elif ! docker image inspect doogs-news-feed:latest >/dev/null 2>&1; then
  warn "Build doogs-news-feed:latest before starting Compose."
else
  say "Starting the full stack"
  docker compose --profile monitoring-agent up -d
  docker compose --profile monitoring-agent ps
fi

say "Bootstrap complete"
echo "Configure Cloudflare Tunnel hostnames to target http://traefik:80."
echo "Use RESTORE.md to restore app data and install the restic timer."
