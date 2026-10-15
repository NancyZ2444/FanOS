"""Run durable image transfers: python -m app.modules.catalog.media_worker [--once]."""

from __future__ import annotations

import argparse
import fcntl
import logging
import time
from datetime import UTC, datetime, timedelta

from sqlalchemy import or_, select

from app.core.config import get_settings
from app.core.database import SessionLocal
from app.future_models import OutboxEvent
from app.modules.catalog.media_import import EVENT, apply_image, backfill, store_image, target_data

log = logging.getLogger(__name__)


def process_pending(limit=10) -> int:
    root = get_settings().local_media_root
    root.mkdir(parents=True, exist_ok=True)
    processed = 0
    # One consumer on the shared media volume; a crash releases the lock.
    with (root / ".catalog-media-worker.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        with SessionLocal() as db:
            events = db.scalars(
                select(OutboxEvent)
                .where(
                    OutboxEvent.event_type == EVENT,
                    OutboxEvent.published_at.is_(None),
                    or_(
                        OutboxEvent.publish_attempts < 5,
                        OutboxEvent.payload["state"].as_string() == "downloading",
                    ),
                )
                .order_by(OutboxEvent.occurred_at)
            ).all()
            attempted = 0
            for event in events:
                if event.publish_attempts >= 5:
                    event.payload = {**event.payload, "state": "failed"}
                    event.last_error = "上次下载中断，已达到自动重试上限，请手动重试"
                    db.commit()
                    continue
                retry_at = event.payload.get("next_attempt_at")
                if retry_at and datetime.fromisoformat(retry_at) > datetime.now(UTC):
                    continue
                if attempted >= limit:
                    break
                attempted += 1
                _, _, data = target_data(db, event.aggregate_type, event.aggregate_id)
                if data.get(event.payload["field"]) != event.payload["source_url"]:
                    event.payload = {**event.payload, "state": "superseded"}
                    event.published_at = datetime.now(UTC)
                    db.commit()
                    continue
                event.publish_attempts += 1
                event.payload = {**event.payload, "state": "downloading"}
                db.commit()
                try:
                    stored, thumbnail = store_image(event.payload["source_url"])
                    # expire_all ensures the comparison sees edits committed during download.
                    db.expire_all()
                    applied = apply_image(db, event, stored, thumbnail)
                    event.payload = {
                        **event.payload,
                        "state": "ready" if applied else "superseded",
                        "stored_url": stored,
                        "thumbnail_url": thumbnail,
                    }
                    event.last_error = None
                    event.published_at = datetime.now(UTC)
                    processed += int(applied)
                    db.commit()
                except Exception as exc:
                    db.rollback()
                    event.payload = {
                        **event.payload,
                        "state": "failed" if event.publish_attempts >= 5 else "retrying",
                        "next_attempt_at": (
                            datetime.now(UTC) + timedelta(seconds=30 * 2**event.publish_attempts)
                        ).isoformat(),
                    }
                    event.last_error = str(exc)[:300]
                    db.commit()
                    log.warning("Catalog media task %s failed (%s)", event.id, type(exc).__name__)
    return processed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--once", action="store_true")
    parser.add_argument(
        "--backfill", action="store_true", help="Queue historical images, idempotently"
    )
    args = parser.parse_args()
    if args.backfill:
        with SessionLocal() as db:
            count = backfill(db)
            db.commit()
            print(f"Queued {count} images. Existing images and catalog IDs are preserved.")
        return
    while True:
        process_pending()
        if args.once:
            return
        time.sleep(10)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
