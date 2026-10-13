"""Read-only SQLite catalog audit. Never guesses historical identity or changes rows."""
import argparse
import hashlib
import json
import sqlite3
from pathlib import Path


def audit(path):
    db = sqlite3.connect(f"file:{Path(path).resolve()}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    tables = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
    snapshots = {}
    for table in sorted(tables):
        rows = [dict(r) for r in db.execute(f'SELECT * FROM "{table}"')]
        canonical = sorted(json.dumps(r, sort_keys=True, ensure_ascii=False, default=str) for r in rows)
        snapshots[table] = {"rows":len(rows),"sha256":hashlib.sha256("\n".join(canonical).encode()).hexdigest()}
    metadata = {(r["entity_type"],r["entity_id"]):json.loads(r["data"] or "{}") for r in db.execute("SELECT * FROM admin_content_metadata")} if "admin_content_metadata" in tables else {}
    proposals = []
    for table, kind in [("catalog_albums","albums"),("catalog_events","events"),("catalog_collections","collections"),("catalog_merchandise","merchandise")]:
        for row in db.execute(f'SELECT * FROM "{table}"'):
            data = metadata.get((kind,row["id"]),{})
            if row["group_id"] and not data.get("artists"):
                proposals.append({"kind":kind,"id":row["id"],"issue":"legacy_artist_relation","safe_proposal":[{"type":"groups","id":row["group_id"]}],"requires_confirmation":False})
    for card in db.execute("SELECT * FROM cards"):
        data = json.loads(card["admin_data"] or "{}")
        if not data.get("source_entity_id"):
            matches = []
            for table,kind in [("catalog_albums","albums"),("catalog_events","events"),("catalog_collections","collections"),("catalog_merchandise","merchandise")]:
                matches += [{"type":kind,"id":r["id"]} for r in db.execute(f'SELECT id FROM "{table}" WHERE name=? AND group_id IS ?', (card["source"],card["group_id"]))]
            proposals.append({"kind":"cards","id":card["id"],"issue":"legacy_source_without_id","candidates":matches,"requires_confirmation":len(matches)!=1})
        if card["version"] and not data.get("entity_version_id"):
            proposals.append({"kind":"cards","id":card["id"],"issue":"version_text_without_relation","version":card["version"],"requires_confirmation":True})
        if card["idol_id"] and card["group_id"] and card["release_date"]:
            released = str(card["release_date"]).replace(".","-")
            periods = list(db.execute("SELECT * FROM group_memberships WHERE idol_id=? AND group_id=?", (card["idol_id"],card["group_id"])))
            if not any(str(m["start_date"]) <= released and (not m["end_date"] or released <= str(m["end_date"])) for m in periods):
                proposals.append({"kind":"cards","id":card["id"],"issue":"historical_membership_dates_missing_or_conflicting","requires_confirmation":True})
    db.close()
    return {"read_only":True,"tables":snapshots,"upgrade_candidates":proposals,"policy":"Preserve IDs, attribution, user ownership and history; no inferred dates."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database")
    parser.add_argument("--output")
    args = parser.parse_args()
    report = audit(args.database)
    encoded = json.dumps(report,ensure_ascii=False,indent=2)
    if args.output:
        Path(args.output).write_text(encoded)
        print(f"Read-only audit: {len(report['upgrade_candidates'])} candidates; {args.output}")
    else:
        print(encoded)
