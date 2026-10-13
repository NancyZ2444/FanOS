"""Preview/apply approved album normalization with backup and row-level preservation checks."""

import argparse
import hashlib
import json
import sqlite3
import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps/api"))

from app.modules.admin.album_normalization import normalize_albums
from sqlalchemy import create_engine
from sqlalchemy.orm import Session


def snapshot(connection):
    tables = [
        r[0]
        for r in connection.exec_driver_sql(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
    ]
    return {
        table: {
            str(
                r.get("id", json.dumps(dict(r), sort_keys=True, default=str))
            ): json.dumps(dict(r), sort_keys=True, ensure_ascii=False, default=str)
            for r in connection.exec_driver_sql(f'SELECT * FROM "{table}"').mappings()
        }
        for table in tables
    }


def hashes(rows):
    return {
        table: {
            "rows": len(values),
            "sha256": hashlib.sha256(
                "\n".join(sorted(values.values())).encode()
            ).hexdigest(),
        }
        for table, values in rows.items()
    }


def verify_preservation(before, after, report):
    allowed_updates = {
        "catalog_albums": set(report["touched_album_ids"]),
        "admin_content_metadata": set(report["touched_metadata_ids"]),
    }
    allowed_additions = {
        "catalog_operational_records": set(
            report["versions_created"] + report["legacy_versions_created"]
        ),
        "operation_logs": None,
    }
    if before.keys() != after.keys():
        raise RuntimeError("Table schema changed; transaction rolled back")
    for table, old_rows in before.items():
        for key, value in old_rows.items():
            if key not in after[table] or (
                key not in allowed_updates.get(table, set())
                and after[table][key] != value
            ):
                raise RuntimeError(
                    f"Unrelated original row changed: {table}/{key}; rolled back"
                )
        added = after[table].keys() - old_rows.keys()
        if added and (
            table not in allowed_additions
            or (
                allowed_additions[table] is not None
                and not added <= allowed_additions[table]
            )
        ):
            raise RuntimeError(
                f"Unexpected rows added: {table}; transaction rolled back"
            )
    return sorted(table for table in before if before[table] == after[table])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--output", required=True, help="New JSON report path")
    args = parser.parse_args()
    path, output = Path(args.database).resolve(), Path(args.output).resolve()
    if not path.is_file() or output.exists():
        parser.error("Database must exist and report must not already exist")
    output.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    if args.apply:
        backup = output.with_name(
            f"album-backup-{datetime.now(UTC):%Y%m%d-%H%M%S-%f}.db"
        )
        with (
            sqlite3.connect(f"file:{path}?mode=ro", uri=True) as source,
            sqlite3.connect(backup) as target,
        ):
            source.backup(target)
    url = (
        f"sqlite:///{path}" if args.apply else f"sqlite:///file:{path}?mode=ro&uri=true"
    )
    with Session(create_engine(url)) as db:
        # Reserve writer before capturing baseline so concurrent edits cannot pass checks.
        if args.apply:
            db.connection().exec_driver_sql("BEGIN IMMEDIATE")
        before = snapshot(db.connection())
        report = normalize_albums(db, apply=args.apply)
        after = snapshot(db.connection())
        unchanged = (
            verify_preservation(before, after, report) if args.apply else sorted(before)
        )
        if args.apply:
            db.commit()
        report.update(
            backup=str(backup) if backup else None,
            before=hashes(before),
            after=hashes(after),
            unchanged_tables=unchanged,
            preservation_verified=True,
        )
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {
                "applied": args.apply,
                "families": len(report["families"]),
                "versions_created": len(report["versions_created"]),
                "legacy_versions_created": len(report["legacy_versions_created"]),
                "unchanged_tables": len(unchanged),
                "backup": report["backup"],
                "report": str(output),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
