# Kinescope — чат по базе знаний (Algolia Agent на Vercel)

Чат с ассистентом по документации Kinescope. Запросы идут через API route `/api/chat` (прокси на сервере Vercel) в Algolia Agent Studio — обход CORS, ключ не в браузере.

Стек: **Next.js**, стрим ответа (SSE, события `text-delta`). Совместимо с форматом AI SDK 5.

## Локальный запуск

```bash
cd algolia-chat-vercel
npm install
npm run dev
```

Откройте [http://localhost:3000](http://localhost:3000).

## Деплой на Vercel

1. Залейте проект в GitHub (или подключите репозиторий к Vercel).
2. В [Vercel](https://vercel.com): **Add New Project** → импортируйте репозиторий.
3. **Root Directory** укажите `algolia-chat-vercel` (если проект в подпапке монорепо).
4. Задайте переменные окружения (обязательно для ответов агента):
   - `ALGOLIA_APPLICATION_ID` — Application ID (например `SRC8UTYBUO`)
   - `ALGOLIA_API_KEY` — API key с доступом к Agent Studio
   - `ALGOLIA_AGENT_ID` — ID агента из Agent Studio (опубликованный агент)
   Запросы к Algolia идут через API route `/api/chat` на сервере (обход CORS, ключ не в браузере).
5. **Deploy**.

После деплоя чат будет доступен по ссылке вида `https://your-project.vercel.app`.

## Производительность

- **Прокси** стримит ответ чанками без буферизации по строкам — быстрее первый байт.
- **US-эндпоинт**: задайте `ALGOLIA_AGENT_STUDIO_BASE_URL=https://agent-studio.us.algolia.com` в Vercel, если деплой в США (меньше RTT до Algolia).
- **Первый запрос** после простоя может быть медленнее (cold start serverless).

## Безопасность

Ключ Algolia задаётся только на сервере (`ALGOLIA_*` в Vercel). Браузер обращается к `/api/chat`, прокси стримит ответ от Algolia — ключ в клиент не попадает.
