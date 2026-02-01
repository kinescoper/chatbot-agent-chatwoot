# Обработка qdrant-find в MCP-сервере

Код разнесён: MCP только вызывает поиск, вызов Qdrant и разбор ответа — в `rag/search.py`.

---

## 1. MCP-сервер: обработка инструмента qdrant-find

**Файл:** `mcp_server/server.py`

```python
@app.call_tool()
async def call_tool(name: str, arguments: dict[str, Any]) -> list[types.ContentBlock]:
    if name != "qdrant-find":
        return [types.TextContent(type="text", text=f"Unknown tool: {name}")]
    query = (arguments or {}).get("query") or ""
    if not query.strip():
        return [types.TextContent(type="text", text="Укажите query для поиска.")]
    try:
        text = await _search_async(query)
        return [types.TextContent(type="text", text=text)]
    except Exception as e:
        return [types.TextContent(type="text", text=f"Ошибка поиска: {e}")]
```

Поиск выполняется через `_search_async(query)` → `rag_search(query)` из модуля `rag.search`.

---

## 2. Вызов Qdrant и разбор ответа

**Файл:** `rag/search.py`

Используется **`client.query_points()`** (не `search()`). Ответ — объект с полем **`points`**; у каждого элемента — **`score`** и **`payload`**.

### Запрос к Qdrant

```python
response = client.query_points(
    collection_name=COLLECTION_NAME,
    query=v,
    using=VECTOR_NAME,
    limit=lf,
    with_payload=True,
)
```

### Парсинг ответа

```python
results = getattr(response, "points", []) or []
if not results:
    return f"По запросу «{q}» ничего не найдено."
```

Из ответа берётся `response.points`; если его нет или пусто — считается, что результатов нет.

### Обработка каждого результата (hit)

- **`hit`** — элемент из `response.points` (в qdrant-client это объект типа `ScoredPoint`).
- **`hit.score`** — число (релевантность).
- **`hit.payload`** — словарь с полями, заданными при индексации.

Формирование текста результата:

```python
for i, hit in enumerate(results, 1):
    score = getattr(hit, "score", None)
    payload = getattr(hit, "payload", None) or {}
    section = payload.get("section", "")
    source = payload.get("source", "")
    content = payload.get("content", "").strip()
    lines.append(f"{i}. (score: {score:.3f}) {section}")
    lines.append(f"   Источник: {source}")
    if content:
        lines.append(f"   Текст: {content}")
    lines.append("")
```

То же чтение `score` и `payload` используется при ре-ранжировании (keyword / cross-encoder):

```python
for hit in hits:
    payload = getattr(hit, "payload", None) or {}
    content = (payload.get("content") or "").strip()
    vec_score = float(getattr(hit, "score", 0.0))
    # ...
```

---

## 3. Сводка

| Что | Где | Как |
|-----|-----|-----|
| Обработка инструмента `qdrant-find` | `mcp_server/server.py` | `call_tool` → `_search_async(query)` → `rag_search(query)` |
| Вызов Qdrant | `rag/search.py` | `client.query_points(..., with_payload=True)` |
| Ответ | `rag/search.py` | `response.points` — список точек |
| Одна точка | элемент из `points` | `getattr(hit, "score", None)`, `getattr(hit, "payload", None)` или `{}` |
| Поля из payload | те же места | `payload.get("section")`, `payload.get("source")`, `payload.get("content")` |

Итого: ответ от Qdrant парсится так — **`response.points`** → для каждого **`hit`** берутся **`hit.score`** и **`hit.payload`**, из payload — `section`, `source`, `content`.
