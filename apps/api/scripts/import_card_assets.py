#!/usr/bin/env python3
"""Import manually supplied official-card photos into storage and card-matcher."""
# ruff: noqa: E402

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image
from sqlalchemy import select

API_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(API_ROOT))

from app.common.events import enqueue_outbox
from app.core.config import get_settings  # noqa: E402
from app.core.database import SessionLocal, create_schema  # noqa: E402
from app.integrations.storage import get_storage  # noqa: E402
from app.models import Card  # noqa: E402
from app.modules.admin.catalog_jobs import process_pending

SUPPORTED = {".jpg", ".jpeg", ".png", ".webp"}


def find_front_images(root: Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in SUPPORTED:
            continue
        if path.name.startswith("_") or "back" in path.stem.lower():
            continue
        yield path


def card_id_for(path: Path) -> str:
    if path.stem.lower() == "front" or path.parent.name.startswith(("card-", "card_")):
        return path.parent.name
    return path.stem


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Import official card fronts from assets/import/cards/<card-id>/front.jpg"
    )
    parser.add_argument(
        "root",
        nargs="?",
        type=Path,
        default=API_ROOT.parents[1] / "assets" / "import" / "cards",
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--rebuild-existing",
        action="store_true",
        help="Reindex existing database photos from configured storage",
    )
    args = parser.parse_args()
    if not args.root.is_dir():
        raise SystemExit(f"照片目录不存在: {args.root}")

    create_schema()
    settings = get_settings()
    imported = 0
    skipped = 0
    with SessionLocal() as db:
        known_ids = set(db.scalars(select(Card.id)).all())
        if args.rebuild_existing:
            for card in db.scalars(select(Card).where(Card.image_url.is_not(None))):
                print(f"[reindex] {card.id}")
                if not args.dry_run:
                    enqueue_outbox(
                        db,
                        event_type="catalog.card.image.updated",
                        aggregate_type="card",
                        aggregate_id=card.id,
                        payload={"image_url": card.image_url},
                    )
        for path in find_front_images(args.root):
            card_id = card_id_for(path)
            if card_id not in known_ids:
                print(f"[skip] {path}: 数据库中不存在 Card ID {card_id}")
                skipped += 1
                continue
            print(f"[import] {card_id} <- {path}")
            if args.dry_run:
                imported += 1
                continue
            content = path.read_bytes()
            with Image.open(path) as image:
                image.verify()
            image_url = get_storage().save_bytes(content, path.name, f"cards/{card_id}")
            db.get(Card, card_id).image_url = image_url
            enqueue_outbox(
                db,
                event_type="catalog.card.image.updated",
                aggregate_type="card",
                aggregate_id=card_id,
                payload={"image_url": image_url},
            )
            imported += 1
        if not args.dry_run:
            db.commit()
    if not args.dry_run:
        while process_pending():
            pass
    print(f"完成：导入 {imported} 张，跳过 {skipped} 张；索引 {settings.card_matcher_index_path}")


if __name__ == "__main__":
    main()
