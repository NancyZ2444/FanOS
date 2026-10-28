"""Single local worker for the versioned JSON card-artwork feature index.

Run `python -m app.modules.admin.catalog_jobs --once` or without --once for polling.
Only reads images from configured object storage. Never fetches arbitrary URLs.
"""

from __future__ import annotations

import argparse
import fcntl
import io
import json
import logging
import os
import time
from datetime import UTC, datetime

from PIL import Image
from sqlalchemy import select

from app.core.config import get_settings
from app.core.database import SessionLocal
from app.future_models import OutboxEvent
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.integrations.storage import get_storage
from app.models import Card

log = logging.getLogger(__name__)


def storage_bytes(url: str) -> bytes:
    return get_storage().read_bytes(url)


def process_pending() -> int:
    settings = get_settings()
    path = settings.card_matcher_index_path
    path.parent.mkdir(parents=True, exist_ok=True)
    processed = 0
    # This worker owns one JSON index. Serialize readers of its read/modify/write cycle.
    with open(str(path) + ".lock", "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        with SessionLocal() as db:
            events = db.scalars(
                select(OutboxEvent)
                .where(
                    OutboxEvent.event_type == "catalog.card.image.updated",
                    OutboxEvent.published_at.is_(None),
                    OutboxEvent.publish_attempts < 5,
                )
                .order_by(OutboxEvent.occurred_at)
                .limit(20)
            ).all()
            for event in events:
                card = db.get(Card, event.aggregate_id)
                if not card or card.image_url != event.payload["image_url"]:
                    event.published_at = datetime.now(UTC)
                    db.commit()
                    continue
                event.publish_attempts += 1
                event.payload = {
                    **event.payload,
                    "processing_started_at": datetime.now(UTC).isoformat(),
                    "processing_finished_at": None,
                }
                db.commit()
                try:
                    current = json.loads(path.read_text()) if path.exists() else []
                    if not isinstance(current, list):
                        raise ValueError("索引格式错误，请检查索引文件后重试")
                    image = Image.open(io.BytesIO(storage_bytes(card.image_url))).convert("RGB")
                    adapter = CardMatcherAdapter()
                    entry = adapter.index_entry(card.id, image, card.image_url)
                    current = [r for r in current if r["card_id"] != card.id]
                    current.append(entry)
                    temporary = path.with_suffix(".tmp")
                    temporary.write_text(json.dumps(current, ensure_ascii=False))
                    os.replace(temporary, path)
                    event.published_at = datetime.now(UTC)
                    event.last_error = None
                    processed += 1
                except Exception as exc:
                    event.last_error = str(exc)[:500]
                    log.warning("Card index update failed for %s: %s", card.id, exc)
                event.payload = {
                    **event.payload,
                    "processing_finished_at": datetime.now(UTC).isoformat(),
                }
                db.commit()
    return processed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    while True:
        process_pending()
        if args.once:
            break
        time.sleep(10)


if __name__ == "__main__":
    main()
