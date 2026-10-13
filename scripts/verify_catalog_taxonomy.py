"""Read-only verification of a migrated SQLite database against a saved backup.

Usage: python scripts/verify_catalog_taxonomy.py BEFORE.db AFTER.db
Does not connect to the API or create/modify records.
"""

import argparse
import hashlib
import json
import sqlite3
from pathlib import Path


def digest(db):
    tables = {}
    for (table,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
        rows = db.execute(f'SELECT * FROM "{table}" ORDER BY 1').fetchall()
        tables[table] = {
            "count": len(rows),
            "hash": hashlib.sha256(
                json.dumps(rows, ensure_ascii=False, default=str).encode()
            ).hexdigest(),
        }
    return tables


def verify(before_path, after_path):
    with (
        sqlite3.connect(f"file:{before_path}?mode=ro", uri=True) as before,
        sqlite3.connect(f"file:{after_path}?mode=ro", uri=True) as after,
    ):
        old, new = digest(before), digest(after)
        changed = {
            table: {"before": old.get(table, {}).get("count"), "after": data["count"]}
            for table, data in new.items()
            if data["hash"] != old.get(table, {}).get("hash")
        }
        issues = []
        for table in ("catalog_collections", "catalog_merchandise"):
            for id, name in before.execute(f'SELECT id, name FROM "{table}"'):
                row = after.execute(
                    "SELECT name, legacy_data FROM catalog_others WHERE id=?", (id,)
                ).fetchone()
                if not row or row[0] != name:
                    issues.append(f"Missing or renamed source: {id}")
        for id, raw in before.execute("SELECT id, admin_data FROM cards"):
            data = json.loads(raw or "{}")
            if data.get("source_entity_type") not in {"COLLECTION", "MERCHANDISE"}:
                continue
            updated = json.loads(
                after.execute("SELECT admin_data FROM cards WHERE id=?", (id,)).fetchone()[0]
            )
            if updated.get("source_entity_type") != "OTHER" or updated.get(
                "source_entity_id"
            ) != data.get("source_entity_id"):
                issues.append(f"Changed or missing card source identity: {id}")
        for table in old:
            if table not in new or old[table]["count"] != new[table]["count"]:
                if table not in {"admin_content_metadata", "catalog_operational_records"}:
                    issues.append(f"Unexpected row count change: {table}")
        protected = {
            "groups",
            "idols",
            "group_memberships",
            "catalog_albums",
            "catalog_events",
            "users",
            "user_collection_items",
            "user_wishlist_items",
            "card_albums",
            "album_cards",
            "album_pages",
            "album_slots",
            "album_images",
        }
        for table in protected & old.keys():
            if old[table]["hash"] != new.get(table, {}).get("hash"):
                issues.append(f"Protected table changed: {table}")
        integrity = [r[0] for r in after.execute("PRAGMA integrity_check")]
        foreign_keys = after.execute("PRAGMA foreign_key_check").fetchall()
        if integrity != ["ok"] or foreign_keys:
            issues.append("Database integrity or foreign key failure")
        return {
            "changed_tables": changed,
            "unchanged_tables": len(old) - len(set(changed) & old.keys()),
            "integrity_check": integrity,
            "foreign_key_errors": foreign_keys,
            "issues": issues,
            "migration_head": after.execute("SELECT version_num FROM alembic_version").fetchone()[
                0
            ],
        }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    result = verify(args.before.resolve(), args.after.resolve())
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(1 if result["issues"] else 0)
