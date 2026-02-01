# Payload при записи, логи MCP и проверка коллекции papers

## 1. Код записи в Qdrant — как формируется payload

Отдельного модуля «qdrant-store» в репозитории нет. Запись в Qdrant выполняется в **`scripts/index_to_qdrant.py`**.

### Формирование payload при записи

```python
# scripts/index_to_qdrant.py, ~строки 134–146
points = [
    PointStruct(
        id=str(uuid.uuid4()),
        vector={VECTOR_NAME: vectors[i]},
        payload={
            "section": section,   # иерархия/путь (например, "getting-started")
            "source": source,    # URL (https://docs.kinescope.ru/...)
            "content": chunk,    # текст чанка
            "heading": heading, # последний заголовок Markdown (## / ###) блока
        },
        ...
    )
    for i, (section, source, chunk, heading) in enumerate(items)
]
client.upsert(collection_name=COLLECTION_NAME, points=batch)
```

### Ключи payload

| Ключ     | Тип   | Описание |
|----------|--------|----------|
| `section` | string | Путь/раздел (из относительного пути файла) |
| `source`  | string | URL страницы (docs.kinescope.ru/...) |
| `content` | string | Текст чанка |
| `heading` | string | Заголовок блока (## / ###) или пустая строка |

В `rag/search.py` при поиске читаются те же ключи: `section`, `source`, `content`. Ключ `heading` при формировании ответа не используется (можно добавить в вывод при необходимости).

---

## 2. Логи MCP-сервера и полный traceback

MCP по умолчанию работает через stdio; stderr уходит в процесс, который его запускает (Cursor/IDE). Чтобы увидеть полный traceback при ошибке поиска, сделано два изменения.

### 2.1 Traceback в тексте ответа инструмента

При любой ошибке в `qdrant-find` в ответ пользователю теперь возвращается полный traceback (см. код в `mcp_server/server.py`). В Cursor он будет виден в ответе инструмента «qdrant-find».

### 2.2 Как смотреть логи MCP вручную

Запуск MCP «вручную» в терминале, чтобы stderr был виден:

```bash
cd /path/to/test_mcp
# с виртуальным окружением
source .venv/bin/activate
export QDRANT_URL=http://localhost:6333
export COLLECTION_NAME=papers

# Запуск сервера (stdio). Сообщения об ошибках пойдут в stderr.
python -m mcp_server.server
```

Или через uvx (как в конфиге):

```bash
QDRANT_URL=http://localhost:6333 COLLECTION_NAME=papers uvx mcp-server-qdrant
```

Пока сервер ждёт ввод, любые исключения и логи будут выводиться в этот терминал. Для полноценного вызова инструмента нужен MCP-клиент (например, временно поменять в Cursor команду запуска MCP на `python -m mcp_server.server` и смотреть вывод в терминале/логах Cursor, если он их показывает).

---

## 3. Содержимое коллекции papers — структура payload

### Через скрипт в репозитории

Скрипт **`scripts/inspect_qdrant_payload.py`** подключается к Qdrant, делает scroll по коллекции `papers` и выводит ключи payload и примеры записей (по умолчанию первые 5 точек). Запуск:

```bash
python scripts/inspect_qdrant_payload.py
```

Опционально: лимит точек и URL Qdrant:

```bash
LIMIT=10 QDRANT_URL=http://localhost:6333 python scripts/inspect_qdrant_payload.py
```

### Через Qdrant HTTP API

- Информация о коллекции:
  - `GET http://localhost:6333/collections/papers`
- Scroll (первые точки с payload):
  - `POST http://localhost:6333/collections/papers/points/scroll`
  - Body: `{"limit": 5, "with_payload": true, "with_vector": false}`

Пример (curl):

```bash
curl -s -X POST "http://localhost:6333/collections/papers/points/scroll" \
  -H "Content-Type: application/json" \
  -d '{"limit": 5, "with_payload": true}' | jq .
```

В ответе у каждого элемента из `result.points` будут поля `id`, `payload` (и при запросе — `vector`). По ним можно сверить ключи (`section`, `source`, `content`, `heading`) со схемой выше.

### Через Qdrant UI

В веб-интерфейсе Qdrant (если настроен): коллекция **papers** → просмотр точек → для каждой точки отображается payload с теми же ключами.

---

## Краткая сводка

| Вопрос | Где смотреть |
|--------|----------------|
| Как формируется payload при записи и какие ключи? | `scripts/index_to_qdrant.py`, ключи: `section`, `source`, `content`, `heading` |
| Что именно падает в MCP и полный traceback? | Ответ инструмента `qdrant-find` при ошибке (traceback в тексте) + stderr при ручном запуске `python -m mcp_server.server` |
| Какая структура payload у записей в коллекции? | `scripts/inspect_qdrant_payload.py` или `POST .../collections/papers/points/scroll` с `with_payload: true` |
