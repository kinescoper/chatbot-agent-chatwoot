#!/usr/bin/env python3
"""
Экспорт коллекции papers из Qdrant в файл data/qdrant_papers_export.jsonl.
Нужен для переноса базы на удалённый сервер: запустить локально, скопировать data/ на сервер, там выполнить restore_qdrant_collection.py.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DATA_DIR = REPO_ROOT / "data"
EXPORT_FILE = DATA_DIR / "qdrant_papers_export.jsonl"

QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333")
COLLECTION_NAME = os.environ.get("COLLECTION_NAME", "papers")
VECTOR_NAME = "fast-all-minilm-l6-v2"


def main() -> None:
    from qdrant_client import QdrantClient

    client = QdrantClient(url=QDRANT_URL)
    if not client.collection_exists(COLLECTION_NAME):
        print(f"Коллекция {COLLECTION_NAME!r} не найдена.", file=sys.stderr)
        sys.exit(1)

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    count = 0
    offset = None
    with open(EXPORT_FILE, "w", encoding="utf-8") as f:
        while True:
            records, offset = client.scroll(
                collection_name=COLLECTION_NAME,
                limit=100,
                offset=offset,
                with_vectors=True,
                with_payload=True,
            )
            if not records:
                break
            for rec in records:
                vec = rec.vector
                if isinstance(vec, dict):
                    vec = vec.get(VECTOR_NAME, vec)
                if hasattr(vec, "tolist"):
                    vec = vec.tolist()
                point = {
                    "id": str(rec.id),
                    "vector": vec,
                    "payload": rec.payload or {},
                }
                f.write(json.dumps(point, ensure_ascii=False) + "\n")
                count += 1
            if offset is None:
                break
    print(f"Экспортировано {count} точек в {EXPORT_FILE}")
    print("Скопируйте папку data/ на сервер и выполните: python scripts/restore_qdrant_collection.py")


if __name__ == "__main__":
    main()
