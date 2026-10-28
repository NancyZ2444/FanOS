"""Initialize immutable dossier snapshots; dry-run by default, SQLite backup required."""

import argparse
import json
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sqlalchemy import select

from app.common.response import DomainError
from app.core.database import SessionLocal, engine
from app.modules.catalog import profiles

parser = argparse.ArgumentParser()
parser.add_argument("--apply", action="store_true")
parser.add_argument("--backup", type=Path)
args = parser.parse_args()
if args.apply:
    if engine.url.get_backend_name() != "sqlite" or not args.backup:
        raise SystemExit("Apply requires a local SQLite database and --backup")
    source = Path(engine.url.database).resolve()
    if not source.is_file() or args.backup.exists() or args.backup.resolve() == source:
        raise SystemExit("Source must exist and backup must be a new, different file")
    args.backup.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(f"file:{source}?mode=ro", uri=True) as old:
        with sqlite3.connect(args.backup) as backup:
            old.backup(backup)

with SessionLocal() as db:
    pending = []
    before = {}
    for kind in ("groups", "idols"):
        for row in db.scalars(select(profiles.catalog.MODELS[kind])):
            try:
                value = profiles.snapshot(db, kind, row.id)
            except DomainError as error:
                if error.status_code == 404:
                    continue
                raise
            before[(kind, row.id)] = value
            if not profiles.latest(db, kind, row.id):
                pending.append((kind, row.id))
    if args.apply:
        for target in pending:
            profiles.initialize(db, *target)
        for target, snapshot in before.items():
            assert profiles.snapshot(db, *target) == snapshot, "Initialization changed public facts"
        db.commit()
    print(
        json.dumps(
            {
                "applied": args.apply,
                "public_profiles": len(before),
                "initialized": len(pending),
                "backup": str(args.backup) if args.apply else None,
            },
            ensure_ascii=False,
        )
    )
