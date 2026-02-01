#!/usr/bin/env bash
# Deploy RAG chat project to VPS (gdrant-agent).
# Usage: ./scripts/deploy-to-vps.sh [--no-sync]
# Requires: rsync, ssh with Host gdrant-agent in ~/.ssh/config.
# .env must already exist on the VPS (not synced).

set -e

VPS_HOST="gdrant-agent"
REMOTE_DIR="/opt/rag-chat"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

do_sync=1
for arg in "$@"; do
  if [[ "$arg" == "--no-sync" ]]; then
    do_sync=0
  fi
done

if [[ "$do_sync" -eq 1 ]]; then
  echo "==> Syncing project to $VPS_HOST:$REMOTE_DIR ..."
  rsync -avz \
    --exclude .git \
    --exclude .venv \
    --exclude .venv-indexer \
    --exclude __pycache__ \
    --exclude .env \
    --exclude "*.pyc" \
    --exclude .DS_Store \
    -e "ssh" \
    "$PROJECT_ROOT/" \
    "$VPS_HOST:$REMOTE_DIR/"
fi

echo "==> Running docker compose on VPS ..."
ssh "$VPS_HOST" "cd $REMOTE_DIR && docker compose up -d --build"

echo "==> Healthcheck (backend) ..."
for i in 1 2 3 4 5; do
  if ssh "$VPS_HOST" "curl -sf http://localhost:8000/health" 2>/dev/null; then
    echo ""
    echo "Deploy done. Chat: http://<VPS_IP>:8000"
    exit 0
  fi
  sleep 3
done

echo "Healthcheck failed (backend may still be starting). Check: ssh $VPS_HOST 'docker compose -f $REMOTE_DIR/docker-compose.yml logs -f backend'"
exit 1
