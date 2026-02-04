# Chatwoot + Pre Chat Form: развилка «AI агент / человек»

Подход к интеграции чата Chatwoot с AI-бэкендом (например RAG + LLM): пользователь в виджете выбирает «поговорить с ботом» или «с человеком» через **Pre Chat Form**; webhook на нашем бэкенде получает сообщения и в режиме «бот» отвечает через AI, в режиме «человек» — присылает подсказку оператору (copilot).

Код сделан **портируемым**: его можно использовать в других проектах с Chatwoot, подставив свой AI-бэкенд. **URL бэкенда настраивается в Chatwoot** — при переносе RAG на другой сервер меняется только webhook URL в настройках Chatwoot.

---

## 1. Что делает интеграция

- **Pre Chat Form** в Chatwoot собирает атрибут `support_mode`: «bot» (AI агент) или «human» (человек).
- При новом сообщении Chatwoot шлёт webhook на ваш бэкенд (`POST /chatwoot/webhook`).
- Бэкенд по `support_mode` из conversation (или contact):
  - **bot** — вызывает ваш AI (например RAG+LLM), постит ответ в чат как исходящее сообщение (видит клиент).
  - **human** — вызывает AI и постит результат как **приватную заметку** (видят только операторы, copilot).
- Сообщения, содержащие **только email** (поля Pre Chat Form «Get notified by email») или с `content_type: input_email`, **не отправляются в RAG** и по ним ответ не постится — чтобы не показывать «не нашёл» на ввод контактного email.
- Текст сообщения от Chatwoot может приходить с HTML-тегами (`<p>...</p>`). Перед поиском по базе знаний теги удаляются, чтобы RAG получал обычный текст.
- Сразу после получения сообщения (режим bot) в чат постится автоответ: «Спасибо за обращение. Наш AI ассистент уже работает над ответом, подождите пожалуйста несколько секунд.» — затем в фоне формируется ответ по базе знаний и постится вторым сообщением. **Опционально:** при `CHATWOOT_STREAM_REPLY=true` ответ стримится блоками (по абзацам/предложениям): placeholder не постится, в чат уходят несколько сообщений по мере генерации — создаётся эффект «печатает».
- В логах бэкенда пишутся тайминги: `rag_sec` (поиск по Qdrant), `llm_sec` (вызов LLM), `total_sec`. Для ускорения можно уменьшить объём поиска: в `.env` задать `LIMIT_FIRST=10` и `LIMIT_FINAL=3` (ценой небольшого снижения полноты ответа).

Эндпоинты:

| Метод | Путь | Назначение |
|-------|------|------------|
| POST | `/chatwoot/webhook` | Webhook от Chatwoot (event `message_created`). |
| POST | `/chatwoot/copilot` | Тело `{"message": "..."}` — возвращает только подсказку, без поста в Chatwoot. |

---

## 2. Настройка Chatwoot (вручную)

Без этих шагов в виджете **не появится** выбор «AI агент» / «Человек» — форма будет стандартной (email и т.д.).

### Шаг 1: Custom attribute для Conversation

- Зайдите в **Settings** (шестерёнка) → **Custom Attributes** → **Add**.
- **Applies to:** выберите **Conversation** (не Contact).
- **Display Name:** подпись для отображения, например «Кому написать?» или «Support mode».
- **Key:** укажите **только** `support_mode` — латиница, без пробелов и скобок. Не пишите в Key ничего вроде `(List: bot, human)` — иначе Chatwoot покажет «Key is required». Значения списка задаются отдельно (см. ниже).
- **Description:** по желанию, например «Выбор: AI агент или оператор».
- **Type:** выберите **List** (не Text).
- **Values** (значения списка): добавьте два варианта, например:
  - `bot` (отображаемое имя можно задать «AI агент»),
  - `human` («Человек»).
- Сохраните.

### Шаг 2: Включить поле в Pre Chat Form инбокса

- **Settings** → **Inboxes** → выберите **Website**-инбокс, который используется на testchat.kn.pe (тот, чей website token вставлен в виджет).
- Откройте вкладку **Pre Chat Form** (или раздел настроек формы перед чатом).
- В списке полей найдите атрибут **support_mode** и **включите** его (галочка / toggle).
- Задайте подпись для посетителя, например: «Кому написать?» или «Выберите: AI агент или оператор».
- Сохраните настройки инбокса.

После этого при открытии чата (в том числе в инкогнито) сначала показывается форма с выбором «AI агент» / «Человек», затем уже диалог.

**Не спрашивать email, если выбран «AI агент»:** в Chatwoot нельзя включить условное отображение полей (показывать email только при выборе «Человек»). Зато можно сделать поле **Email в Pre Chat Form необязательным**: **Settings → Inboxes → ваш Website-инбокс → Pre Chat Form** — для поля Email снимите галочку **Required**. Тогда пользователь, выбрав «AI агент», может оставить email пустым и сразу начать диалог; для «Человек» оператор сможет запросить контакт в первом сообщении или пользователь сам заполнит email по желанию.

### Шаг 3: Webhook (обязательно — иначе Chatwoot не вызывает наш бэкенд)

В наших конфигах URL бэкенда **не задаётся**. Его нужно указать вручную в Chatwoot:

- **Settings** → **Integrations** → **Webhooks** → **Add**:
  - URL: `https://agent.kn.pe/chatwoot/webhook` (для kn.pe; если бэкенд на другом хосте — подставьте его URL).
  - Subscribe to: **message_created**.
- Сохраните.

Подробнее: [CHATWOOT-WEBHOOK-SETUP.md](CHATWOOT-WEBHOOK-SETUP.md).

Если вы развернёте RAG-бэкенд на **другом сервере**, измените только этот URL. Переменные окружения задаются на том сервере, где крутится бэкенд.

---

## 3. Переменные окружения (бэкенд)

| Переменная | Описание |
|------------|----------|
| `CHATWOOT_BASE_URL` | URL инстанса Chatwoot (например `https://chatwoot.yourcompany.com`). |
| `CHATWOOT_ACCOUNT_ID` | ID аккаунта (число). |
| `CHATWOOT_API_ACCESS_TOKEN` | Токен из Profile → Access Token в Chatwoot. |
| `CHATWOOT_SUPPORT_MODE_ATTR` | Ключ атрибута в custom_attributes (по умолчанию `support_mode`). |
| `CHATWOOT_STREAM_REPLY` | `true` — ответ бота постится блоками (стриминг по абзацам); `false` (по умолчанию) — одно сообщение + placeholder. |
| `CHATWOOT_STREAM_MIN_CHARS` | Минимальная длина блока при стриминге (по умолчанию 120). |
| `CHATWOOT_STREAM_MAX_CHARS` | Максимальная длина блока (по умолчанию 450). |
| `CHATWOOT_AGENTBOT_INBOX_ID` | Один id инбокса «всегда бот» (без Pre Chat Form), например `2` для Test Chat AgentBot. |
| `CHATWOOT_AGENTBOT_INBOX_IDS` | Несколько id через запятую (альтернатива `CHATWOOT_AGENTBOT_INBOX_ID`). |
| `CHATWOOT_AGENTBOT_ACCESS_TOKEN` | Токен Agent Bot (Chatwoot Settings → Bots): ответы для agentbot-инбокса постим от имени бота. |

Без первых трёх переменных webhook будет принимать запросы, но не будет постить ответы в Chatwoot (логируется предупреждение).

**Откат стриминга:** чтобы вернуть режим «одно сообщение + placeholder» (без блоков), в `.env` задайте `CHATWOOT_STREAM_REPLY=false` или удалите переменную, затем перезапустите backend: `docker compose restart backend` (или `docker compose -f /path/to/docker-compose.yml restart backend` на VPS).

**Если в логах бэкенда есть «Chatwoot client not configured; skipping webhook processing»** — на сервере, где крутится бэкенд (например VPS), в `.env` не заданы или пусты `CHATWOOT_BASE_URL`, `CHATWOOT_ACCOUNT_ID` или `CHATWOOT_API_ACCESS_TOKEN`. Добавьте их в `.env` в каталоге развёртывания (например `/opt/rag-chat/.env`), затем перезапустите контейнеры (`docker compose up -d`). Откуда взять значения: **CHATWOOT_BASE_URL** — URL вашего Chatwoot (например `https://chatwoot.kn.pe`); **CHATWOOT_ACCOUNT_ID** — число, видно в URL при открытии настроек аккаунта в Chatwoot; **CHATWOOT_API_ACCESS_TOKEN** — в Chatwoot: профиль (аватар) → **Access Token** → создать токен с правами на отправку сообщений.

**Если в логах «post_message failed … status=401»** — Chatwoot не принимает токен. Частая причина на self-hosted: **nginx по умолчанию отбрасывает заголовки с подчёркиванием** (в т.ч. `api_access_token`). В конфиге виртуального хоста Chatwoot (например `chatwoot.kn.pe.conf`) добавьте `underscores_in_headers on;` в блок `server` и выполните `nginx -t && nginx -s reload`. Альтернативно проверьте токен: `curl -s "https://ВАШ_CHATWOOT/api/v1/profile" -H "api_access_token: ВАШ_ТОКЕН"` — при правильной настройке nginx и токене вернётся JSON профиля, а не 401. Нужен **персональный** Access Token именно с вашего инстанса (например `https://chatwoot.kn.pe`): зайдите в этот же адрес → аватар → **Profile** → внизу страницы **Access Token** → создайте новый токен и подставьте в `CHATWOOT_API_ACCESS_TOKEN`. Убедитесь, что `CHATWOOT_ACCOUNT_ID` совпадает с ID аккаунта в URL (например `/app/accounts/1/` → `1`). Токены от Chatwoot Cloud (app.chatwoot.com) для self-hosted не подходят.

**Отладка «ответ не пришёл»:** в логах бэкенда смотрите строки `chatwoot webhook:` и `chatwoot webhook process:`. Там будет: пришёл ли запрос (event, message_type, conversation_id), `inbox_id`, какой `support_mode` применён, вызван ли reply provider, успешно ли отправлено сообщение в Chatwoot.

---

## 3.1. Второй инбокс: testchat-agentbot.kn.pe (всегда бот)

На поддомене **testchat-agentbot.kn.pe** развёрнут виджет с инбоксом **Test Chat AgentBot** (без Pre Chat Form): пользователь сразу пишет в чат, все сообщения обрабатываются как режим «бот». В Chatwoot создан Agent Bot **Qdrant** с webhook `https://agent.kn.pe/chatwoot/webhook`, бот привязан к этому инбоксу. Бэкенд определяет инбокс по `inbox_id` в webhook payload. Задайте в `.env`: `CHATWOOT_AGENTBOT_INBOX_ID=2` (id инбокса Test Chat AgentBot, см. URL настроек инбокса в Chatwoot). Опционально: `CHATWOOT_AGENTBOT_ACCESS_TOKEN` — токен бота Qdrant, чтобы ответы в чате отображались от имени бота. Деплой лендинга: `./scripts/setup-testchat-agentbot-kn-pe.sh`. Ошибки отправки в Chatwoot пишутся как `Chatwoot client: post_message failed` со статусом и телом ответа. На VPS: `docker compose -f /opt/rag-chat/docker-compose.yml logs -f backend`.

---

## 4. Тайминги и ускорение ответа

Чтобы понять, где тратится время (RAG vs LLM), в логах бэкенда пишутся замеры:

- **rag_sec** — время поиска по Qdrant (эмбеддинг + запрос + ре-ранжирование).
- **llm_sec** — время вызова LLM (один запрос к OpenAI-совместимому API).
- **total_sec** — полное время от старта обработки сообщения до постинга ответа (в stderr: `[chatwoot] reply_len=... total_sec=...`).

**Как посмотреть тайминги на VPS:**

```bash
docker compose -f /opt/rag-chat/docker-compose.yml logs backend 2>&1 | tail -100
```

Убедитесь, что уровень логирования не ниже INFO (по умолчанию так и есть). Строки вида `get_rag_reply: query_len=... rag_sec=...` и `get_rag_reply: llm_sec=... total_sec=...` идут из RAG-модуля; `[chatwoot] ... total_sec=...` — из webhook.

**Что можно ускорить:**

| Что | Как |
|-----|-----|
| RAG | В `.env` уменьшить объём поиска: `LIMIT_FIRST=10`, `LIMIT_FINAL=3` (чуть меньше контекста для LLM, но быстрее). Если используете cross-encoder (`USE_CROSS_ENCODER=true`), отключение его ускоряет ре-ранжирование. |
| LLM | Выбрать более быструю модель (например `gpt-4o-mini` вместо `gpt-4o`), или другой провайдер с меньшей задержкой. |
| Сеть | Qdrant и LLM API ближе к серверу бэкенда (тот же регион/датацентр) уменьшают задержки. |

После смены `LIMIT_*` или модели перезапустите backend и повторите запрос, сравнив тайминги в логах.

---

## 5. Индикатор «печатает» (typing)

В Chatwoot **нет Application API** для отображения «бот печатает»: эндпоинт [Toggle typing status](https://developers.chatwoot.com/api-reference/conversations-api/toggle-typing-status) относится к **Client (Public) API** и предназначен для того, чтобы **контакт** (пользователь в виджете) сообщал «я печатаю». Им пользуется фронтенд виджета; с бэкенда через наш `api_access_token` этот сценарий не реализовать без знания идентификаторов инбокса и контакта из Public API и другой авторизации.

**Что уже есть:** сразу после получения сообщения в режиме bot в чат постится короткое сообщение: *«Спасибо за обращение. Наш AI ассистент уже работает над ответом, подождите пожалуйста несколько секунд.»* — это даёт пользователю явную обратную связь, что ответ готовится.

**Возможные доработки (без изменения Chatwoot):**

- В **кастомном виджете** (свой фронтенд вместо стандартного bubble): после отправки сообщения показывать локальный индикатор «Ассистент печатает…» и скрывать его при получении следующего исходящего сообщения в этот разговор (по WebSocket или при обновлении списка сообщений).
- Оставить текущий вариант с одним мгновенным автоответом — для многих сценариев этого достаточно.

---

## 6. Портируемость: использование в другом проекте

Интеграция не привязана к конкретному RAG/LLM. Нужны два модуля и «провайдер ответа».

### 6.1 Модули

- **`backend/chatwoot_client.py`** — отправка сообщений в Chatwoot (Application API). Зависит только от `httpx` и env.
- **`backend/chatwoot_webhook.py`** — разбор webhook, определение `support_mode`, вызов провайдера ответа и отправка в Chatwoot. **Не импортирует** ваш RAG/LLM; ответы получает через инъекцию.

### 6.2 Провайдер ответа

Провайдер — функция `(message: str) -> str | None`. Её задаёт хост-приложение:

```python
from backend.chatwoot_webhook import router as chatwoot_router, set_reply_provider

def my_ai_reply(user_message: str) -> str | None:
    # Ваша логика: RAG, другой API, и т.д.
    return "Ответ пользователю"

set_reply_provider(my_ai_reply)
app.include_router(chatwoot_router)
```

Скопируйте `chatwoot_client.py` и `chatwoot_webhook.py` в свой проект, настройте env, зарегистрируйте роутер и вызовите `set_reply_provider(ваша_функция)` перед `include_router`. Эндпоинты будут под префиксом `/chatwoot` (webhook и copilot).

### 6.3 Замена хоста бэкенда

- Webhook вызывается **Chatwoot’ом** на тот URL, который вы указали в настройках Webhooks. Хост бэкенда = тот сервер, где слушает ваш FastAPI (или другой фреймворк с тем же путём `/chatwoot/webhook`).
- Чтобы «перенести» RAG на другой сервер: разверните там приложение с тем же роутом и env, затем в Chatwoot замените URL webhook на `https://новый-хост/chatwoot/webhook`. Код менять не нужно.

---

## 7. Откуда берётся support_mode

Сначала проверяется **conversation** (Pre Chat Form), затем **contact** (например если атрибут задаётся через SDK):

- `conversation.custom_attributes.support_mode` или `additional_attributes`
- `contact.custom_attributes.support_mode` или `additional_attributes`
- Альтернативный ключ: `preferred_channel` (то же значение `bot` / `human`).

**Если атрибуты пустые** (первое сообщение до отправки формы): по умолчанию **human** — ответ постится как приватная заметка оператору, клиент не видит его. Так мы не показываем «не нашёл» на служебные/не-вопросы. После выбора «AI агент» в форме атрибуты заполняются и последующие ответы идут публично (bot). Сообщения только с email и короткие служебные фразы виджета («Get notified by email», «Please enter your email») пропускаются — RAG не вызывается.

---

## 8. Ссылки

- [Chatwoot: Pre-chat forms](https://www.chatwoot.com/hc/user-guide/articles/1677688647-how-to-use-pre_chat-forms)
- [Chatwoot: Webhooks](https://www.chatwoot.com/hc/user-guide/articles/1677693021-how-to-use-webhooks)
- [Chatwoot API: Create message](https://developers.chatwoot.com/api-reference/messages/create-new-message)
