# Поддомены kn.pe: chatwoot.kn.pe и agent.kn.pe

Разнесение доступа по поддоменам на одном VPS.

## Выполнение плана (одной командой)

После того как A-записи **agent.kn.pe** и **chatwoot.kn.pe** указывают на IP VPS, с локальной машины выполните:

```bash
./scripts/setup-subdomains-and-chatwoot.sh
```

Скрипт:

1. Синхронизирует проект на VPS (rsync).
2. Запустит backend (RAG) через `docker compose`.
3. Установит nginx и certbot (если ещё не стоят), скопирует лендинг в `/var/www/kn.pe`.
4. **kn.pe**: при отсутствии SSL — bootstrap и certbot; затем включит конфиг с лендингом.
5. **agent.kn.pe**: bootstrap (HTTP) → certbot → полный конфиг с HTTPS (прокси на backend:8000). Проверит наличие SSL; если сертификата нет — получит.
6. **chatwoot.kn.pe**: bootstrap → certbot → полный конфиг с HTTPS (прокси на :3000). Установит SSL для Chatwoot.
7. Установит Chatwoot в `/opt/chatwoot`: клонирует репозиторий, создаёт `.env` (FRONTEND_URL=https://chatwoot.kn.pe, сгенерированные POSTGRES_PASSWORD и REDIS_PASSWORD), запускает `docker compose -f docker-compose.production.yaml up -d`.

Переменные (при необходимости):

- `VPS_HOST=gdrant-agent` — SSH Host из `~/.ssh/config`.
- `CERTBOT_EMAIL=admin@kn.pe` — email для Let's Encrypt.
- `CHATWOOT_DIR=/opt/chatwoot` — каталог установки Chatwoot.

После выполнения проверьте: https://kn.pe (лендинг), https://agent.kn.pe (RAG чат), https://chatwoot.kn.pe (Chatwoot). Первый запуск Chatwoot может занять 1–2 минуты.

**Если Chatwoot «битый»** (пустой интерфейс My Inbox, ошибки при логине) — переустановите с нуля одним скриптом (применяются все известные фиксы): `./scripts/chatwoot-reinstall.sh`. Подробнее: [scripts/chatwoot-fixes/README.md](../scripts/chatwoot-fixes/README.md).

---

## Да, так можно

Если вы добавите **A-записи** для поддоменов на IP вашего VPS:

- `chatwoot.kn.pe` → IP VPS  
- `agent.kn.pe` → IP VPS  

то на одном сервере nginx будет различать запросы по полю **Host** и направлять их в разные приложения. Один IP — несколько доменов/поддоменов, это стандартная схема.

## Схема

| Поддомен / домен | Назначение | Бэкенд на VPS |
|------------------|------------|----------------|
| **kn.pe** | Лендинг со списком сервисов (статическая страница со ссылками) | nginx: `root /var/www/kn.pe` |
| **agent.kn.pe** | RAG API и webhook для Chatwoot (`/chat`, `/chatwoot/webhook`, `/chatwoot/copilot`) | `backend:8000` |
| **chatwoot.kn.pe** | Интерфейс Chatwoot (агенты, виджет) | Chatwoot Rails (порт 3000) |
| **testchat.kn.pe** | Тестовая страница с виджетом Chatwoot (Pre Chat Form: AI агент / человек) | nginx: `root /var/www/testchat.kn.pe` |
| **testchat-agentbot.kn.pe** | Тестовая страница с виджетом «всегда бот» (инбокс Test Chat AgentBot, без формы) | nginx: `root /var/www/testchat-agentbot.kn.pe` |

На **kn.pe** отображаются две ссылки: Chatwoot и Knowledge base web chat (agent.kn.pe).

## Шаги

### 1. DNS

У регистратора/хостинга DNS для домена **kn.pe** добавьте A-записи:

- **chatwoot.kn.pe** → IP вашего VPS  
- **agent.kn.pe** → IP вашего VPS  
- **testchat.kn.pe** → IP вашего VPS (опционально; для теста виджета Chatwoot)

(Запись для **kn.pe** у вас уже есть.)

### 2. Nginx на VPS

- Конфиг **kn.pe** (`nginx/kn.pe.conf`) отдаёт статическую страницу из `/var/www/kn.pe`. Скопируйте лендинг на VPS:
  ```bash
  sudo mkdir -p /var/www/kn.pe
  sudo cp /opt/rag-chat/nginx/kn.pe-landing/index.html /var/www/kn.pe/
  ```
- Добавлены конфиги:
  - `nginx/agent.kn.pe.conf` — прокси на `127.0.0.1:8000` (ваш backend).
  - `nginx/chatwoot.kn.pe.conf` — прокси на `127.0.0.1:3000` (Chatwoot Rails).

Скопируйте их на сервер и подключите:

```bash
# На VPS (или через скрипт с локальной машины)
sudo cp /opt/rag-chat/nginx/agent.kn.pe.conf   /etc/nginx/sites-available/
sudo cp /opt/rag-chat/nginx/chatwoot.kn.pe.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/agent.kn.pe.conf   /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/chatwoot.kn.pe.conf /etc/nginx/sites-enabled/
```

Перед включением HTTPS в этих конфигах получите сертификаты (см. ниже).

### 3. HTTPS (Let's Encrypt)

Сначала в конфигах для **agent** и **chatwoot** оставьте только блоки `listen 80` (без `return 301 https://...` и без блоков `listen 443`), либо временно используйте конфиги только с HTTP. Затем:

```bash
sudo certbot --nginx -d agent.kn.pe -d chatwoot.kn.pe
```

Certbot сам добавит редирект на HTTPS и пути к сертификатам. Либо вручную после выдачи сертификатов подставьте в конфиги пути вида:

- `/etc/letsencrypt/live/agent.kn.pe/...`
- `/etc/letsencrypt/live/chatwoot.kn.pe/...`

и включите блоки `server { listen 443 ssl; ... }` из репозитория.

Проверка и перезагрузка nginx:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 4. Chatwoot на VPS

Chatwoot ставится отдельно от вашего RAG-проекта (отдельный каталог, свой docker-compose):

1. Клонируйте репозиторий Chatwoot или возьмите [docker-compose для production](https://github.com/chatwoot/chatwoot/blob/develop/docker-compose.production.yaml).
2. В `.env` Chatwoot укажите:
   - `FRONTEND_URL=https://chatwoot.kn.pe`
   - Остальные переменные по [документации](https://www.chatwoot.com/docs/self-hosted/deployment/docker) (Postgres, Redis, секреты и т.д.).
3. Запустите: `docker compose -f docker-compose.production.yaml up -d`.
4. Rails будет слушать `127.0.0.1:3000` — nginx по `chatwoot.kn.pe` уже проксирует на этот порт.

### 5. RAG backend (agent.kn.pe)

Ваш текущий проект с Qdrant и FastAPI уже слушает порт 8000. Достаточно, чтобы nginx для **agent.kn.pe** проксировал на `127.0.0.1:8000` (конфиг `agent.kn.pe.conf` это делает).

### 6. testchat.kn.pe (тест виджета Chatwoot)

Статическая страница с встроенным виджетом Chatwoot (inbox script) для проверки взаимодействия с инбоксом. A-запись **testchat.kn.pe** → IP VPS.

С локальной машины (проект синхронизирован на VPS):

```bash
./scripts/setup-testchat-kn-pe.sh
```

Скрипт: синхронизирует проект, создаёт `/var/www/testchat.kn.pe`, копирует `nginx/testchat.kn.pe-landing/*`, включает bootstrap-конфиг, получает сертификат certbot для testchat.kn.pe, подключает полный конфиг с HTTPS и перезагружает nginx. Опционально: `CERTBOT_EMAIL=you@example.com`.

После выполнения откройте **https://testchat.kn.pe** — на странице загружается виджет Chatwoot (websiteToken и baseUrl заданы в `nginx/testchat.kn.pe-landing/index.html`).

**Если пузырь чата не появляется (429 на /widget):** Chatwoot по умолчанию ограничивает запросы к виджету (Rack::Attack). На сервере, где запущен Chatwoot, в `.env` добавьте и перезапустите контейнеры:
```bash
# Отключить rate limit для API виджета (устраняет 429 на /widget)
ENABLE_RACK_ATTACK_WIDGET_API=false
```
Документация: [Chatwoot Rate Limiting](https://developers.chatwoot.com/self-hosted/monitoring/rate-limiting). Альтернативно можно увеличить лимит: `RACK_ATTACK_LIMIT=300`.

### 7. testchat-agentbot.kn.pe (виджет «всегда бот»)

Дубликат тестового чата без Pre Chat Form: инбокс **Test Chat AgentBot**, все диалоги обрабатываются как ответ бота. A-запись **testchat-agentbot.kn.pe** → IP VPS. В бэкенде задайте `CHATWOOT_AGENTBOT_INBOX_ID=2` (id инбокса в Chatwoot). Деплой:

```bash
./scripts/setup-testchat-agentbot-kn-pe.sh
```

После выполнения откройте **https://testchat-agentbot.kn.pe**. Подробнее: [CHATWOOT-PRE-CHAT-FORM.md](CHATWOOT-PRE-CHAT-FORM.md) (раздел 3.1).

---

В Chatwoot в настройках webhook укажите URL:

- `https://agent.kn.pe/chatwoot/webhook`

В `.env` backend (вашего RAG-проекта) укажите:

- `CHATWOOT_BASE_URL=https://chatwoot.kn.pe`
- `CHATWOOT_ACCOUNT_ID=...`
- `CHATWOOT_API_ACCESS_TOKEN=...`

## Итог

- **A-записи** `chatwoot.kn.pe` и `agent.kn.pe` на один IP VPS — достаточно.
- **Nginx** по `Host` разводит трафик: chatwoot.kn.pe → 3000, agent.kn.pe → 8000, kn.pe — как у вас сейчас.
- **Chatwoot** — отдельный деплой (docker-compose Chatwoot) на том же VPS, доступ по https://chatwoot.kn.pe.
- **RAG и webhook** — ваш backend на 8000, доступ по https://agent.kn.pe; в Chatwoot указываете webhook `https://agent.kn.pe/chatwoot/webhook`.

Конфиги nginx для поддоменов лежат в репозитории: `nginx/agent.kn.pe.conf`, `nginx/chatwoot.kn.pe.conf`.
