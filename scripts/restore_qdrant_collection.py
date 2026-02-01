#!/usr/bin/env python3
"""
Восстановление коллекции papers в Qdrant из файла data/qdrant_papers_export.jsonl.
Запускать на сервере после docker compose up (Qdrant уже работает). Укажите QDRANT_URL (например http://localhost:6333).
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
EXPORT_FILE = REPO_ROOT / "data" / "qdrant_papers_export.jsonl"

QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333")
COLLECTION_NAME = os.environ.get("COLLECTION_NAME", "papers")
VECTOR_NAME = "fast-all-minilm-l6-v2"
VECTOR_SIZE = 384


def main() -> None:
    from qdrant_client import QdrantClient
    from qdrant_client.models import Distance, PointStruct, VectorParams

    if not EXPORT_FILE.exists():
        print(f"Файл не найден: {EXPORT_FILE}", file=sys.stderr)
        print("Сначала выполните export_qdrant_collection.py на машине с заполненной коллекцией.", file=sys.stderr)
        sys.exit(1)

    client = QdrantClient(url=QDRANT_URL)
    if client.collection_exists(COLLECTION_NAME):
        client.delete_collection(COLLECTION_NAME)
    client.create_collection(
        collection_name=COLLECTION_NAME,
        vectors_config={
            VECTOR_NAME: VectorParams(size=VECTOR_SIZE, distance=Distance.COSINE),
        },
    )

    points = []
    with open(EXPORT_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            points.append(
                PointStruct(
                    id=obj["id"],
                    vector={VECTOR_NAME: obj["vector"]},
                    payload=obj["payload"],
                )
            )

    if not points:
        print("В файле нет точек.", file=sys.stderr)
        sys.exit(1)

    batch_size = 100
    for i in range(0, len(points), batch_size):
        batch = points[i : i + batch_size]
        client.upsert(collection_name=COLLECTION_NAME, points=batch)
    print(f"Восстановлено {len(points)} точек в коллекции {COLLECTION_NAME!r}.")


if __name__ == "__main__":
    main()
