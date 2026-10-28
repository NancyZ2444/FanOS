"""Resolve explicitly approved legacy IDs and verify a migration against its backup."""

import argparse
import json
import sqlite3
from collections import Counter
from pathlib import Path

from sqlalchemy import select

from app.album_models import AlbumWork
from app.core.database import SessionLocal
from app.models import CardAlbum
from app.modules.albums.migration_v11 import migrate_works
from app.modules.albums.service import document, occupied

parser = argparse.ArgumentParser()
parser.add_argument("--backup", type=Path, required=True)
parser.add_argument("--cards", action="append", default=[])
args = parser.parse_args()
before = sqlite3.connect(f"file:{args.backup.resolve()}?mode=ro", uri=True)
before.row_factory = sqlite3.Row
originals = {r["id"]: dict(r) for r in before.execute("select * from card_albums")}
with SessionLocal() as db:
    if args.cards:
        assert set(args.cards) <= originals.keys(), "Unknown resolution IDs"
        migrate_works(db, {id: "CARDS" for id in args.cards})
    report = []
    rows = db.scalars(select(CardAlbum)).all()
    assert {r.id for r in rows} == originals.keys(), "Work IDs changed"
    for row in rows:
        old = originals[row.id]
        for key in (
            "user_id",
            "name",
            "is_public",
            "status",
            "revision",
            "sort_order",
            "is_moderated",
        ):
            assert getattr(row, key) == old[key], (row.id, key)
        assert str(row.updated_at).rstrip("0").rstrip(".") == old["updated_at"].rstrip("0").rstrip(
            "."
        ), (row.id, "timestamp")
        work = db.get(AlbumWork, row.id)
        assert work and work.migration_archive, (row.id, "archive missing")
        archived = work.migration_archive["draft"]
        old_cards = Counter(
            s["card_id"] for p in archived["pages"] for s in p["slots"] if s.get("card_id")
        )
        current = document(db, row)
        assert Counter(s["card_id"] for s in occupied(current)) == old_cards, (row.id, "card loss")
        assert work.migration_archive["published"] == json.loads(
            old["published_snapshot"] or "null"
        ), (row.id, "published archive")
        report.append(
            {
                "id": row.id,
                "name": row.name,
                "mode": work.mode,
                "cards": len(occupied(current)),
                "pages": len(current["pages"]),
                "archive_verified": True,
            }
        )
    db.commit()
    print(json.dumps({"verified": True, "works": report}, ensure_ascii=False, indent=2))
