"""Remove retired review queues after backup; retain the current App feedback store.

Preview by default. --apply writes only to the explicitly supplied SQLite database.
"""

import argparse
import hashlib
import json
import sqlite3
from datetime import datetime
from pathlib import Path


def digest_rows(db, table):
    rows = [dict(row) for row in db.execute(f'SELECT * FROM "{table}" ORDER BY id')]
    return hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if not args.database.is_file():
        raise SystemExit("Database does not exist")
    args.output.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(args.database)
    db.row_factory = sqlite3.Row
    before = {
        table: digest_rows(db, table)
        for table in ("catalog_user_feedback", "cards", "groups", "idols", "scan_sessions")
    }
    retired = {
        "scan_feedback": [dict(r) for r in db.execute("SELECT * FROM scan_feedback")],
        "catalog_operational_records": [
            dict(r)
            for r in db.execute("SELECT * FROM catalog_operational_records WHERE kind='reviews'")
        ],
    }
    companies = db.execute(
        "SELECT id,status,data FROM catalog_operational_records WHERE kind='companies'"
    ).fetchall()
    to_backfill = [row for row in companies if "enabled" not in json.loads(row["data"])]
    result = {
        "apply": args.apply,
        "retired_counts": {k: len(v) for k, v in retired.items()},
        "company_enabled_backfill": len(to_backfill),
        "protected_counts": {
            table: db.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0] for table in before
        },
    }
    if args.apply:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup = args.output / f"before-cleanup-{stamp}.db"
        with sqlite3.connect(backup) as target:
            db.backup(target)
        backup.chmod(0o600)
        archive = args.output / f"retired-queue-{stamp}.json"
        archive.write_text(json.dumps(retired, ensure_ascii=False, indent=2))
        archive.chmod(0o600)
        with db:
            db.execute("DELETE FROM scan_feedback")
            db.execute("DELETE FROM catalog_operational_records WHERE kind='reviews'")
            for row in to_backfill:
                data = json.loads(row["data"])
                if "enabled" not in data:
                    data["enabled"] = row["status"] not in ("OFFLINE", "ARCHIVED")
                    db.execute(
                        "UPDATE catalog_operational_records SET data=? WHERE id=?",
                        (json.dumps(data, ensure_ascii=False), row["id"]),
                    )
            after = {table: digest_rows(db, table) for table in before}
            if before != after:
                raise RuntimeError("Protected business data changed; rolling back")
            if db.execute("PRAGMA foreign_key_check").fetchall():
                raise RuntimeError("Foreign key violation; rolling back")
        result.update(backup=str(backup), archive=str(archive), protected_data_unchanged=True)
    result["integrity"] = db.execute("PRAGMA integrity_check").fetchone()[0]
    (args.output / ("applied.json" if args.apply else "preview.json")).write_text(
        json.dumps(result, ensure_ascii=False, indent=2)
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
