#!/usr/bin/env bash
# Установка nginx на VPS, получение Let's Encrypt сертификата и настройка HTTPS + редирект HTTP->HTTPS.
# Требования: DNS для kn.pe (и www.kn.pe) указывает на IP VPS; backend уже запущен на :8000.
# Запуск: с локальной машины — ./scripts/setup-nginx-vps.sh; на VPS из /opt/rag-chat — VPS_HOST=localhost ./scripts/setup-nginx-vps.sh

set -e

VPS_HOST="${VPS_HOST:-gdrant-agent}"
REMOTE_DIR="${REMOTE_DIR:-/opt/rag-chat}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NGINX_FULL="$PROJECT_ROOT/nginx/kn.pe.conf"
NGINX_BOOTSTRAP="$PROJECT_ROOT/nginx/kn.pe-bootstrap.conf"
DOMAIN="${DOMAIN:-kn.pe}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@$DOMAIN}"

if [[ ! -f "$NGINX_FULL" ]] || [[ ! -f "$NGINX_BOOTSTRAP" ]]; then
  echo "Не найдены конфиги nginx: $NGINX_FULL, $NGINX_BOOTSTRAP" >&2
  exit 1
fi

run_remote() {
  ssh "$VPS_HOST" "$@"
}

copy_conf() {
  local src="$1"
  local name="$2"
  scp "$src" "$VPS_HOST:/tmp/$name"
}

echo "==> Копирование конфигов nginx на $VPS_HOST ..."
copy_conf "$NGINX_BOOTSTRAP" "kn.pe-bootstrap.conf"
copy_conf "$NGINX_FULL" "kn.pe.conf"

echo "==> Установка nginx и certbot на VPS ..."
run_remote "bash -s" "$DOMAIN" "$CERTBOT_EMAIL" << 'REMOTE'
set -e
DOMAIN="${1:-kn.pe}"
CERTBOT_EMAIL="${2:-admin@$DOMAIN}"
apt-get update -qq && apt-get install -y -qq nginx certbot python3-certbot-nginx

# 1) Bootstrap: только HTTP, чтобы certbot мог пройти ACME challenge
cp /tmp/kn.pe-bootstrap.conf /etc/nginx/sites-available/kn.pe.conf
rm -f /tmp/kn.pe-bootstrap.conf
ln -sf /etc/nginx/sites-available/kn.pe.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t && systemctl reload nginx

# 2) Получить сертификат (если ещё нет)
if [[ ! -d /etc/letsencrypt/live/$DOMAIN ]]; then
  if certbot certonly --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "$CERTBOT_EMAIL"; then
    echo "Сертификат Let's Encrypt получен для $DOMAIN"
  else
    echo "Не удалось получить сертификат. Проверьте DNS (kn.pe -> IP VPS) и повторите: certbot certonly --nginx -d $DOMAIN -d www.$DOMAIN"
  fi
fi

# 3) Включить HTTPS + редирект: подменить конфиг на полный (только если есть сертификат)
if [[ -d /etc/letsencrypt/live/$DOMAIN ]] && [[ -f /tmp/kn.pe.conf ]]; then
  cp /tmp/kn.pe.conf /etc/nginx/sites-available/kn.pe.conf
  rm -f /tmp/kn.pe.conf
  echo "Включён HTTPS и редирект HTTP -> HTTPS"
fi
nginx -t && systemctl reload nginx
echo "Nginx: HTTP -> редирект на HTTPS, HTTPS -> http://127.0.0.1:8000"
REMOTE

echo "Готово. Проверьте: https://$DOMAIN/ (DNS должен указывать на IP VPS). Продление сертификата: certbot renew (cron уже настроен пакетом)."
