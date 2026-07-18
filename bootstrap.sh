#!/usr/bin/env bash
#
# Doogster homelab — bootstrap a fresh Debian 13 (Trixie) VM back to the running stack.
#
# This is CONFIG-AS-CODE: it reproduces the STRUCTURE (compose + configs + network + dirs).
# It does NOT restore your data (/mnt/data/personal-apps/*) or secrets.
# See README.md -> "What this does and does NOT do".
#
# Prereqs (do these first):
#   - A data disk mounted at /mnt/data (ext4, in /etc/fstab by UUID with `nofail`). See README.
#   - Run as a normal sudo-capable user (NOT root):  ./bootstrap.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$HOME/stack"
DATA="/mnt/data"
HP_CONFIG="$DATA/personal-apps/homepage/config"

say()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# 0. Sanity checks
[ "$(id -u)" = 0 ] && { warn "Run as a normal user, not root (the script uses sudo where needed)."; exit 1; }
mountpoint -q "$DATA" || { warn "$DATA is not a mountpoint — mount the data disk first (see README)."; exit 1; }

# 1. Docker
if ! command -v docker >/dev/null 2>&1; then
  say "Installing Docker"
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  warn "Added $USER to the 'docker' group — log out/in (or run 'newgrp docker') before continuing."
else
  say "Docker present: $(docker --version)"
fi

# 2. Docker data-root on the big data disk
say "Configuring Docker data-root -> /mnt/data/docker"
sudo mkdir -p /etc/docker "$DATA/docker"
sudo cp "$REPO_DIR/system/daemon.json" /etc/docker/daemon.json
sudo systemctl restart docker

# 3. Persistent data directories
say "Creating data directories under $DATA/personal-apps"
sudo mkdir -p \
  "$HP_CONFIG" \
  "$DATA/personal-apps/linkding" \
  "$DATA/personal-apps/lubelogger/data" \
  "$DATA/personal-apps/lubelogger/keys" \
  "$DATA/personal-apps/beszel/data" \
  "$DATA/personal-apps/beszel/socket" \
  "$DATA/personal-apps/beszel/agent"
sudo chown -R "$USER":"$USER" "$DATA/personal-apps"

# 4. Deploy compose + Homepage config
say "Deploying docker-compose.yml and Homepage config"
mkdir -p "$STACK_DIR"
cp "$REPO_DIR/stack/docker-compose.yml" "$STACK_DIR/docker-compose.yml"
cp "$REPO_DIR"/config/homepage/*.yaml "$HP_CONFIG"/
cp "$REPO_DIR"/config/homepage/*.css  "$HP_CONFIG"/

# 5. Secrets (.env)
if [ ! -f "$STACK_DIR/.env" ]; then
  cp "$REPO_DIR/stack/.env.example" "$STACK_DIR/.env"
  warn "Created $STACK_DIR/.env from the example — FILL IN the real tokens before starting."
fi

# 6. Shared reverse-proxy network (Traefik <-> cloudflared)
say "Ensuring the 'proxy' network exists"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy

# 7. news-feed image (built from the separate app repo)
say "Checking news-feed image"
if docker image inspect doogs-news-feed:latest >/dev/null 2>&1; then
  echo "  doogs-news-feed:latest already present."
elif [ -d "$HOME/news-feed" ]; then
  echo "  Building from ~/news-feed ..."
  docker build -t doogs-news-feed:latest "$HOME/news-feed"
else
  warn "  doogs-news-feed:latest not found and ~/news-feed missing. Build it, e.g.:"
  warn "    git clone https://github.com/aamostcc/doogs-news-feed.git ~/news-feed   # private repo: needs GitHub auth"
  warn "    docker build -t doogs-news-feed:latest ~/news-feed   # repo includes a Dockerfile"
fi

# 8. Start the stack (only if it's safe to)
cd "$STACK_DIR"
if grep -q "replace-with" .env 2>/dev/null; then
  warn "Secrets still contain placeholders. Edit $STACK_DIR/.env, then: docker compose up -d"
elif ! docker image inspect doogs-news-feed:latest >/dev/null 2>&1; then
  warn "Build the news-feed image, then: docker compose up -d"
else
  say "Starting the stack"
  docker compose up -d
  # Beszel agent is behind a profile; start it too if you want host metrics:
  #   docker compose --profile monitoring-agent up -d
  docker compose ps
fi

say "Done."
echo "   Remember: add each app's public hostname in the Cloudflare Tunnel dashboard,"
echo "   pointing at http://traefik:80  (news, links, cars, status, home, traffic)."
