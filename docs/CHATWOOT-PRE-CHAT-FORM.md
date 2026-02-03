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

Эндпоинты:

| Метод | Путь | Назначение |
|-------|------|------------|
| POST | `/chatwoot/webhook` | Webhook от Chatwoot (event `message_created`). |
| POST | `/chatwoot/copilot` | Тело `{"message": "..."}` — возвращает только подсказку, без поста в Chatwoot. |

---

## 2. Настройка Chatwoot (вручную)

1. **Custom attribute для Conversation**  
   Settings → Custom Attributes → Add → **Conversation** attribute:
   - Key: `support_mode`
   - Type: List
   - Values: `bot`, `human` (или отображаемые «AI агент», «Человек»).

2. **Pre Chat Form**  
   Settings → Inboxes → ваш Website inbox → вкладка **Pre Chat Form** → включите поле для атрибута `support_mode`, подпись например «Кому написать?».

3. **Webhook**  
   Settings → Integrations → Webhooks → Add:
   - URL: `https://<хост-вашего-бэкенда>/chatwoot/webhook`
   - Subscribe to: `message_created`.

Если вы развернёте RAG-бэкенд на **другом сервере**, измените только этот URL (например `https://rag-server.example.com/chatwoot/webhook`). Переменные окружения задаются на том сервере, где крутится бэкенд.

---

## 3. Переменные окружения (бэкенд)

| Переменная | Описание |
|------------|----------|
| `CHATWOOT_BASE_URL` | URL инстанса Chatwoot (например `https://chatwoot.yourcompany.com`). |
| `CHATWOOT_ACCOUNT_ID` | ID аккаунта (число). |
| `CHATWOOT_API_ACCESS_TOKEN` | Токен из Profile → Access Token в Chatwoot. |
| `CHATWOOT_SUPPORT_MODE_ATTR` | Ключ атрибута в custom_attributes (по умолчанию `support_mode`). |

Без этих переменных webhook будет принимать запросы, но не будет постить ответы в Chatwoot (логируется предупреждение).

---

## 4. Портируемость: использование в другом проекте

Интеграция не привязана к конкретному RAG/LLM. Нужны два модуля и «провайдер ответа».

### 4.1 Модули

- **`backend/chatwoot_client.py`** — отправка сообщений в Chatwoot (Application API). Зависит только от `httpx` и env.
- **`backend/chatwoot_webhook.py`** — разбор webhook, определение `support_mode`, вызов провайдера ответа и отправка в Chatwoot. **Не импортирует** ваш RAG/LLM; ответы получает через инъекцию.

### 4.2 Провайдер ответа

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

### 4.3 Замена хоста бэкенда

- Webhook вызывается **Chatwoot’ом** на тот URL, который вы указали в настройках Webhooks. Хост бэкенда = тот сервер, где слушает ваш FastAPI (или другой фреймворк с тем же путём `/chatwoot/webhook`).
- Чтобы «перенести» RAG на другой сервер: разверните там приложение с тем же роутом и env, затем в Chatwoot замените URL webhook на `https://новый-хост/chatwoot/webhook`. Код менять не нужно.

---

## 5. Откуда берётся support_mode

Сначала проверяется **conversation** (Pre Chat Form), затем **contact** (например если атрибут задаётся через SDK):

- `conversation.custom_attributes.support_mode` или `additional_attributes`
- `contact.custom_attributes.support_mode` или `additional_attributes`
- Альтернативный ключ: `preferred_channel` (то же значение `bot` / `human`).

Если ничего не найдено, считается режим `human` (copilot).

---

## 6. Ссылки

- [Chatwoot: Pre-chat forms](https://www.chatwoot.com/hc/user-guide/articles/1677688647-how-to-use-pre_chat-forms)
- [Chatwoot: Webhooks](https://www.chatwoot.com/hc/user-guide/articles/1677693021-how-to-use-webhooks)
- [Chatwoot API: Create message](https://developers.chatwoot.com/api-reference/messages/create-new-message)
