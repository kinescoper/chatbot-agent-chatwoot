#!/usr/bin/env python3
"""
Проверка структуры payload в коллекции papers: scroll по точкам,
вывод ключей payload и примеров записей. Для отладки несоответствия payload.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent

QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333")
COLLECTION_NAME = os.environ.get("COLLECTION_NAME", "papers")
VECTOR_NAME = "fast-all-minilm-l6-v2"
LIMIT = int(os.environ.get("LIMIT", "5"))


def main() -> None:
    from qdrant_client import QdrantClient

    client = QdrantClient(url=QDRANT_URL)
    if not client.collection_exists(COLLECTION_NAME):
        print(f"Коллекция {COLLECTION_NAME!r} не найдена.", file=sys.stderr)
        sys.exit(1)

    records, _ = client.scroll(
        collection_name=COLLECTION_NAME,
        limit=LIMIT,
        with_vectors=False,
        with_payload=True,
    )

    if not records:
        print("Коллекция пуста.")
        return

    all_keys: set[str] = set()
    for rec in records:
        p = rec.payload or {}
        all_keys.update(p.keys())

    print(f"Коллекция: {COLLECTION_NAME}, просмотр первых {len(records)} точек.")
    print(f"Ключи payload в выборке: {sorted(all_keys)}\n")

    for i, rec in enumerate(records, 1):
        p = rec.payload or {}
        print(f"--- Точка {i} (id={rec.id}) ---")
        print(json.dumps(p, ensure_ascii=False, indent=2))
        if i < len(records):
            print()
    return


if __name__ == "__main__":
    main()
