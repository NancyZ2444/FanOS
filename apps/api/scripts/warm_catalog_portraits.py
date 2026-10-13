"""Warm derived portraits without modifying catalog records or their original URLs."""

from __future__ import annotations

import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select  # noqa: E402

from app.admin_models import ContentMetadata  # noqa: E402
from app.core.database import SessionLocal  # noqa: E402
from app.modules.catalog.images import cached_thumbnail  # noqa: E402


def warm(item):
    kind, entity_id, source = item
    started = time.perf_counter()
    try:
        path = cached_thumbnail(source)
        return {
            "kind": kind,
            "id": entity_id,
            "bytes": path.stat().st_size,
            "seconds": round(time.perf_counter() - started, 3),
            "status": "ok",
        }
    except Exception as exc:
        return {"kind": kind, "id": entity_id, "status": "error", "error": str(exc)}


if __name__ == "__main__":
    with SessionLocal() as db:
        items = [
            (r.entity_type, r.entity_id, r.data["image_url"])
            for r in db.scalars(
                select(ContentMetadata).where(
                    ContentMetadata.entity_type.in_(["groups", "idols"]),
                    ContentMetadata.status == "PUBLISHED",
                )
            )
            if (r.data or {}).get("image_url")
        ]
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(warm, items))
    print(
        json.dumps(
            {
                "items": results,
                "success": sum(r["status"] == "ok" for r in results),
                "total": len(results),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
