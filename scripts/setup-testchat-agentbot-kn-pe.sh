#!/usr/bin/env bash
# Set up testchat-agentbot.kn.pe: static frontend with Chatwoot widget (always-bot inbox) over TLS.
# Requires: A-record testchat-agentbot.kn.pe → VPS IP; SSH Host gdrant-agent; project synced to VPS.
#
# Run from repo root (or set REMOTE_DIR). Optionally: CERTBOT_EMAIL=you@example.com

set -e
VPS_HOST="${VPS_HOST:-gdrant-agent}"
REMOTE_DIR="${REMOTE_DIR:-/opt/rag-chat}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"

run_remote() { ssh "$VPS_HOST" "$@"; }

echo "==> 1. Sync project to $VPS_HOST ..."
rsync -az --delete \
  --exclude '.git' --exclude '.env' --exclude '__pycache__' --exclude '*.pyc' \
  --exclude 'node_modules' --exclude '.venv*' \
  . "$VPS_HOST:$REMOTE_DIR/"

echo "==> 2. On VPS: disable Qdrant override, create site dir, nginx config, SSL, reload"
run_remote "bash -s" "$REMOTE_DIR" "$CERTBOT_EMAIL" << 'REMOTE'
REMOTE_DIR="$1"
CERTBOT_EMAIL="${2:-admin@kn.pe}"
# На Linux host.docker.internal не резолвится — отключаем override после sync и перезапускаем backend.
if [[ -f "$REMOTE_DIR/docker-compose.override.yml" ]]; then
  mv "$REMOTE_DIR/docker-compose.override.yml" "$REMOTE_DIR/docker-compose.override.yml.bak" 2>/dev/null || true
  cd "$REMOTE_DIR" && docker compose up -d --force-recreate backend 2>/dev/null || true
fi
SITE_ROOT="/var/www/testchat-agentbot.kn.pe"

sudo mkdir -p "$SITE_ROOT"
sudo cp "$REMOTE_DIR/nginx/testchat-agentbot.kn.pe-landing/"* "$SITE_ROOT/"
sudo chown -R www-data:www-data "$SITE_ROOT" 2>/dev/null || true

# Bootstrap (HTTP only) for certbot
sudo cp "$REMOTE_DIR/nginx/testchat-agentbot.kn.pe-bootstrap.conf" /etc/nginx/sites-available/testchat-agentbot.kn.pe.conf
sudo ln -sf /etc/nginx/sites-available/testchat-agentbot.kn.pe.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Get certificate if missing
if [[ ! -d /etc/letsencrypt/live/testchat-agentbot.kn.pe ]]; then
  echo "Getting SSL for testchat-agentbot.kn.pe ..."
  sudo certbot certonly --nginx -d testchat-agentbot.kn.pe --non-interactive --agree-tos -m "$CERTBOT_EMAIL" || true
fi

# Full config with HTTPS
if [[ -d /etc/letsencrypt/live/testchat-agentbot.kn.pe ]]; then
  sudo cp "$REMOTE_DIR/nginx/testchat-agentbot.kn.pe.conf" /etc/nginx/sites-available/testchat-agentbot.kn.pe.conf
  sudo nginx -t && sudo systemctl reload nginx
  echo "testchat-agentbot.kn.pe: HTTPS enabled."
else
  echo "SSL not obtained. Fix DNS/certbot and run again to enable HTTPS."
fi
REMOTE

echo "==> Done. Open https://testchat-agentbot.kn.pe (Chatwoot widget, always-bot inbox)."
echo "    If HTTPS is not ready yet, wait for DNS and run the script again."
