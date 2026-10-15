"""Offline transfer of existing catalog image URLs; never substitutes another photo.

Run inside the API environment. Export is read-only. Import accepts bounded,
checksum-verified files and uses the normal compare-and-set ingestion path.
"""

import argparse
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlsplit

from sqlalchemy import select

from app.core.database import SessionLocal
from app.future_models import OutboxEvent
from app.models import Card
from app.modules.admin.catalog_extensions import CatalogRecord
from app.modules.admin.catalog_service import MODELS
from app.modules.catalog.media_import import (
    EVENT,
    FIELDS,
    apply_image,
    owned_image,
    queue_images,
    store_image_bytes,
    target_data,
    validate_remote,
)


def export_manifest(db):
    items = []
    for kind, model in {**MODELS, "cards": Card, "versions": CatalogRecord}.items():
        query = select(model)
        if kind == "versions":
            query = query.where(CatalogRecord.kind == "versions")
        for row in db.scalars(query):
            _, _, data = target_data(db, kind, row.id)
            for field in FIELDS:
                source = data.get(field)
                if not isinstance(source, str) or not source or owned_image(source):
                    continue
                items.append(
                    {
                        "kind": kind,
                        "id": row.id,
                        "field": field,
                        "source_url": source,
                        "name": getattr(row, "name", getattr(row, "title", row.id)),
                        "host": urlsplit(source).hostname,
                    }
                )
    return {"version": 1, "items": items}


def import_item(db, item, root):
    source = item["source_url"]
    if owned_image(source) or item["field"] not in FIELDS:
        raise ValueError("Only existing external catalog image fields may be imported")
    validate_remote(source)
    path = (root / item["file"]).resolve()
    if not path.is_relative_to(root) or not path.is_file():
        raise ValueError("Invalid transfer file")
    if path.stat().st_size > 20 * 1024 * 1024:
        raise ValueError("Transfer file exceeds limit")
    content = path.read_bytes()
    if hashlib.sha256(content).hexdigest() != item["sha256"]:
        raise ValueError("Transfer checksum differs")
    row, _, data = target_data(db, item["kind"], item["id"])
    if row is None or data.get(item["field"]) != source:
        return "unchanged_or_superseded"
    queue_images(db, item["kind"], item["id"], data)
    db.flush()
    events = db.scalars(
        select(OutboxEvent).where(
            OutboxEvent.event_type == EVENT,
            OutboxEvent.aggregate_type == item["kind"],
            OutboxEvent.aggregate_id == item["id"],
        )
    ).all()
    event = next(
        e
        for e in events
        if e.payload.get("source_url") == source and e.payload.get("field") == item["field"]
    )
    stored, thumbnail = store_image_bytes(source, content)
    applied = apply_image(db, event, stored, thumbnail)
    event.payload = {
        **event.payload,
        "state": "ready" if applied else "superseded",
        "stored_url": stored,
        "thumbnail_url": thumbnail,
        "transfer": "checksum_verified_offline",
        "download_url": item.get("download_url", source),
    }
    event.published_at = datetime.now(UTC)
    event.last_error = None
    return event.payload["state"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["export", "import"])
    parser.add_argument("manifest", nargs="?", type=Path)
    args = parser.parse_args()
    with SessionLocal() as db:
        if args.action == "export":
            print(json.dumps(export_manifest(db), ensure_ascii=False))
            return
        if not args.manifest:
            parser.error("Import requires a manifest")
        manifest = json.loads(args.manifest.read_text())
        if manifest.get("version") != 1:
            raise SystemExit("Unsupported manifest version")
        root = args.manifest.resolve().parent
        results = []
        for item in manifest["items"]:
            if not item.get("file"):
                results.append({"name": item["name"], "state": "not_downloaded"})
                continue
            try:
                state = import_item(db, item, root)
                db.commit()
                results.append({"name": item["name"], "field": item["field"], "state": state})
            except Exception as exc:
                db.rollback()
                results.append({"name": item["name"], "state": "error", "error": str(exc)[:200]})
        print(json.dumps(results, ensure_ascii=False))
        if any(r["state"] in {"error", "not_downloaded"} for r in results):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
