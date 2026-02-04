#!/usr/bin/env bash
# Задаёт Environment Variables проекта algolia-chat-vercel в Vercel через API и запускает деплой.
# Требует: VERCEL_TOKEN, ALGOLIA_API_KEY (или в .env в корне проекта).
# Использование: ALGOLIA_API_KEY=xxx ./scripts/vercel-set-env-and-deploy.sh
#               или положите ALGOLIA_API_KEY в .env и запустите ./scripts/vercel-set-env-and-deploy.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

VERCEL_TOKEN="${VERCEL_TOKEN:-}"
ALGOLIA_API_KEY="${ALGOLIA_API_KEY:-}"
ALGOLIA_APPLICATION_ID="${ALGOLIA_APPLICATION_ID:-SRC8UTYBUO}"
ALGOLIA_AGENT_ID="${ALGOLIA_AGENT_ID:-1feae05a-7e87-4508-88c8-2d7da88e30de}"
# US-эндпоинт уменьшает RTT, если Vercel в США (по умолчанию включаем)
ALGOLIA_AGENT_STUDIO_BASE_URL="${ALGOLIA_AGENT_STUDIO_BASE_URL:-https://agent-studio.us.algolia.com}"
PROJECT_NAME="${VERCEL_PROJECT_NAME:-algolia-chat-vercel}"

if [[ -z "$VERCEL_TOKEN" ]]; then
  echo "Ошибка: задайте VERCEL_TOKEN (токен из https://vercel.com/account/tokens)" >&2
  exit 1
fi

if [[ -z "$ALGOLIA_API_KEY" ]]; then
  echo "Ошибка: задайте ALGOLIA_API_KEY (в .env в корне проекта или export ALGOLIA_API_KEY=...)" >&2
  exit 1
fi

BASE="https://api.vercel.com/v10/projects/${PROJECT_NAME}/env"
AUTH_HEADER="Authorization: Bearer $VERCEL_TOKEN"

# upsert=true — обновить, если переменная уже есть
set_var() {
  local key="$1"
  local value="$2"
  local body
  body=$(printf '%s' "$value" | jq -Rs --arg k "$key" '{ key: $k, value: ., type: "plain", target: ["production", "preview", "development"] }')
  local resp
  resp=$(curl -s -w "\n%{http_code}" -X POST "${BASE}?upsert=true" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "$body")
  local code
  code=$(echo "$resp" | tail -n1)
  local body_only
  body_only=$(echo "$resp" | sed '$d')
  if [[ "$code" != "201" ]]; then
    echo "Ошибка при установке $key (HTTP $code): $body_only" >&2
    return 1
  fi
  echo "  $key — OK"
}

echo "Устанавливаю переменные в проект $PROJECT_NAME ..."
set_var "ALGOLIA_APPLICATION_ID" "$ALGOLIA_APPLICATION_ID"
set_var "ALGOLIA_API_KEY" "$ALGOLIA_API_KEY"
set_var "ALGOLIA_AGENT_ID" "$ALGOLIA_AGENT_ID"
set_var "ALGOLIA_AGENT_STUDIO_BASE_URL" "$ALGOLIA_AGENT_STUDIO_BASE_URL"
echo "Переменные установлены."
echo ""
bash "$SCRIPT_DIR/vercel-deploy.sh"
