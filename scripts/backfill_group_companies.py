"""Preview or apply company backfill with SQLite backup and unchanged-table verification."""

import argparse
import json
import sqlite3
import sys
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps/api"))
from app.modules.admin.company_backfill import backfill_group_companies
from catalog_data_audit import audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument(
        "--output", required=True, help="JSON report; must not already exist"
    )
    args = parser.parse_args()
    path = Path(args.database).resolve()
    output = Path(args.output).resolve()
    if not path.is_file() or output.exists():
        parser.error("Database must exist and output report must not already exist")
    output.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    if args.apply:
        backup = output.with_name(
            f"company-backup-{datetime.now(UTC):%Y%m%d-%H%M%S-%f}.db"
        )
        with (
            sqlite3.connect(f"file:{path}?mode=ro", uri=True) as source,
            sqlite3.connect(backup) as target,
        ):
            source.backup(target)
    before = audit(path)["tables"]
    url = (
        f"sqlite:///{path}" if args.apply else f"sqlite:///file:{path}?mode=ro&uri=true"
    )
    with Session(create_engine(url)) as db:
        report = backfill_group_companies(db, apply=args.apply)
        db.flush() if args.apply else None
        # Check original tables before commit; rollback the entire backfill on any change.
        if args.apply:
            allowed = {"catalog_operational_records", "operation_logs"}
            for table, snapshot in before.items():
                if table in allowed:
                    continue
                rows = (
                    db.connection()
                    .exec_driver_sql(f'SELECT * FROM "{table}"')
                    .mappings()
                    .all()
                )
                import hashlib

                canonical = sorted(
                    json.dumps(dict(r), sort_keys=True, ensure_ascii=False, default=str)
                    for r in rows
                )
                digest = hashlib.sha256("\n".join(canonical).encode()).hexdigest()
                if snapshot != {"rows": len(rows), "sha256": digest}:
                    raise RuntimeError(
                        f"Original table changed: {table}; transaction rolled back"
                    )
            db.commit()
    after = audit(path)["tables"]
    report.update(backup=str(backup) if backup else None, before=before, after=after)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {
                "applied": args.apply,
                "companies": len(report["companies_created"]),
                "relations": len(report["relations_created"]),
                "skipped": len(report["skipped"]),
                "backup": report["backup"],
                "report": str(output),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
