"""Read-only g614 -> j626 release inventory (private, format 2).

Run snapshot before upgrading and compare against that file afterwards. Use the
release API code for both runs, with writers stopped or an isolated restored DB.
Snapshots contain business data and IDs, never authentication credentials.
"""

import argparse
import hashlib
import json
from collections import Counter
from copy import deepcopy
from datetime import UTC, date, datetime

from app.core.database import engine
from sqlalchemy import MetaData, Table, inspect, select

CHANGING = {
    "alembic_version",
    "card_albums",
    "album_cards",
    "digital_album_pages",
    "digital_album_slots",
    "digital_album_resources",
    "digital_album_settings",
    "digital_album_preferences",
    "digital_album_review_requests",
    "digital_album_works",
}
AUTH_TABLES = {
    "auth_admin_principals",
    "auth_sessions",
    "auth_state",
    "auth_challenges",
    "auth_login_whitelist",
    "auth_trusted_identities",
    "auth_audit",
}


def canonical(value):
    if isinstance(value, datetime):
        return value.replace(tzinfo=value.tzinfo or UTC).astimezone(UTC).isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: canonical(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [canonical(item) for item in value]
    return value


def digest(value):
    return hashlib.sha256(
        json.dumps(canonical(value), sort_keys=True, default=str).encode()
    ).hexdigest()


def inventory():
    with engine.connect() as connection:
        db = (
            connection.execution_options(isolation_level="REPEATABLE READ")
            if engine.dialect.name == "postgresql"
            else connection
        )
        if engine.dialect.name == "postgresql":
            db.exec_driver_sql("SET TRANSACTION READ ONLY")
        tables = set(inspect(db).get_table_names())
        meta = MetaData()

        def rows(name):
            if name not in tables:
                return []
            table = Table(name, meta, autoload_with=db)
            return canonical(
                [dict(row) for row in db.execute(select(table)).mappings()]
            )

        protected = {}
        for name in sorted(tables - CHANGING - AUTH_TABLES):
            data = rows(name)
            protected[name] = {
                "count": len(data),
                "hash": digest(sorted(map(digest, data))),
            }
        changing = {name: rows(name) for name in sorted(CHANGING)}
        lock_present = False
        if "auth_state" in tables:
            table = Table("auth_state", meta, autoload_with=db)
            lock_present = (
                db.execute(select(table.c.id).where(table.c.id == "auth-lock")).first()
                is not None
            )
        return {
            "format": 2,
            "tables": sorted(tables),
            "protected": protected,
            "changing": changing,
            "auth_lock_present": lock_present,
        }


def indexed(rows, key="id"):
    return {row[key]: row for row in rows}


def compare(before, after):
    if before.get("format") != 2:
        return [
            "Baseline format is obsolete; take a format=2 snapshot before migration"
        ]
    from app.modules.albums.materials import hydrate_document, references, snapshot
    from app.modules.albums.schemas import CanvasConfig
    from app.modules.albums.service import DEFAULT_RESOURCES

    errors = []
    old, new = before["changing"], after["changing"]

    def equal(actual, expected, label):
        if actual != expected:
            errors.append(label)

    equal(
        old["alembic_version"],
        [{"version_num": "g614_feedback_workflow"}],
        "Expected g614 baseline",
    )
    equal(
        new["alembic_version"],
        [{"version_num": "j626_auth_boundaries"}],
        "Migration head is not j626",
    )
    if not AUTH_TABLES <= set(after["tables"]) or not after["auth_lock_present"]:
        errors.append("Authentication schema/serialization lock missing")
    for name, state in before["protected"].items():
        equal(after["protected"].get(name), state, "Protected table changed: " + name)

    albums, current_albums = indexed(old["card_albums"]), indexed(new["card_albums"])
    works = indexed(new["digital_album_works"], "album_id")
    equal(set(current_albums), set(albums), "Album IDs changed")
    equal(set(works), set(albums), "Work IDs do not match album IDs")
    resources = {r["id"]: deepcopy(r) for r in DEFAULT_RESOURCES}
    resources.update(indexed(deepcopy(old["digital_album_resources"])))
    mapping = {
        r["id"]: r["id"][:40]
        + "-page-"
        + hashlib.sha256(r["id"].encode()).hexdigest()[:10]
        for r in old["digital_album_resources"]
        if r["kind"] != "SHELF"
    }
    used = set()

    def remap(doc):
        result = deepcopy(doc)
        for page in result.get("pages", []):
            config = page.get("config", {})
            background = config.get("background", {})
            if background.get("resource_id") in mapping:
                background["resource_id"] = mapping[background["resource_id"]]
            for element in config.get("elements", []):
                if (
                    element.get("type") == "STICKER"
                    and element.get("content") in mapping
                ):
                    element["content"] = mapping[element["content"]]
        return result

    def convert(doc, mode):
        result = deepcopy(doc)
        result["work_mode"] = mode
        view = result.setdefault("card_view", {})
        view["default_mode"] = mode
        result["card_instances"] = []
        if mode == "CARDS":
            slots = [
                s for p in doc.get("pages", []) for s in p["slots"] if s.get("card_id")
            ]
            by_id = indexed(slots)
            order = (
                list(dict.fromkeys(s for s in view.get("card_order", []) if s in by_id))
                if view.get("order_customized")
                else []
            )
            order += [s["id"] for s in slots if s["id"] not in order]
            result["card_instances"] = [by_id[s] for s in order]
            view["card_order"] = order
            if view.get("featured_slot_id") not in order:
                view["featured_slot_id"] = order[0] if order else None
            view["cover_style"] = "STACK_V1"
            result["cover"], result["pages"] = {}, []
        return result

    def ordered(rows, actual_ids, order_key, label):
        """Allow only undefined ordering among ties; never lose instance identity."""
        by_id = indexed(rows)
        if len(actual_ids) == len(rows) and set(actual_ids) == set(by_id):
            result = [by_id[key] for key in actual_ids]
            equal(
                [r[order_key] for r in result],
                sorted(r[order_key] for r in rows),
                label,
            )
            return result
        errors.append(label + " IDs changed")
        return sorted(rows, key=lambda row: (row[order_key], row["id"]))

    modes, expected_pages, expected_slots, expected_legacy, expected_reviews = (
        {},
        [],
        [],
        [],
        [],
    )
    for aid, album in albums.items():
        work = works.get(aid, {})
        archive = work.get("migration_archive") or {}
        archived_draft = archive.get("draft") or {}
        pages = [p for p in old["digital_album_pages"] if p["album_id"] == aid]
        doc_pages = []
        if pages:
            pages = ordered(
                pages,
                [p["id"] for p in archived_draft.get("pages", [])],
                "page_order",
                "Archived page order: " + aid,
            )
            for page in pages:
                archived_page = next(
                    (
                        p
                        for p in archived_draft.get("pages", [])
                        if p["id"] == page["id"]
                    ),
                    {},
                )
                slots = [
                    s for s in old["digital_album_slots"] if s["page_id"] == page["id"]
                ]
                slots = ordered(
                    slots,
                    [s["id"] for s in archived_page.get("slots", [])],
                    "slot_order",
                    "Archived slot order: " + page["id"],
                )
                doc_pages.append(
                    {
                        "id": page["id"],
                        "grid_count": page["grid_count"],
                        "config": deepcopy(page["page_config"]),
                        "slots": [
                            {"id": s["id"], "card_id": s["card_id"]} for s in slots
                        ],
                    }
                )
        else:
            legacy = [c for c in old["album_cards"] if c["album_id"] == aid]
            actual_ids = [
                s["id"] for p in archived_draft.get("pages", []) for s in p["slots"]
            ]
            legacy = ordered(
                legacy, actual_ids, "sort_order", "Archived legacy order: " + aid
            )
            for index in range(0, len(legacy), 9):
                chunk = legacy[index : index + 9]
                doc_pages.append(
                    {
                        "id": f"legacy-{aid[:45]}-{index // 9}",
                        "grid_count": len(chunk),
                        "config": CanvasConfig().model_dump(),
                        "slots": [
                            {"id": r["id"], "card_id": r["card_id"]} for r in chunk
                        ],
                    }
                )
        draft = {
            "album_id": aid,
            "work_mode": (album["card_view_config"] or {}).get("default_mode", "BOOK"),
            "card_instances": [],
            "name": album["name"],
            "description": album["description"],
            "display_type": album["display_type"],
            "visual_style": album["visual_style"],
            "cover": deepcopy(album["cover_config"]) or CanvasConfig().model_dump(),
            "card_view": deepcopy(album["card_view_config"]),
            "pages": doc_pages,
        }
        draft = hydrate_document(draft, resources)
        published = (
            hydrate_document(deepcopy(album["published_snapshot"]), resources)
            if album["published_snapshot"]
            else None
        )
        reviews = [
            r for r in old["digital_album_review_requests"] if r["album_id"] == aid
        ]
        archived_reviews = {
            r["id"]: hydrate_document(deepcopy(r["snapshot"]), resources)
            for r in reviews
        }
        equal(
            archive,
            {"draft": draft, "published": published, "reviews": archived_reviews},
            "Complete migration archive changed: " + aid,
        )
        used.update(references(draft))
        if published:
            used.update(references(published))
        draft_mode = draft.get("card_view", {}).get("default_mode")
        published_mode = (published or {}).get("card_view", {}).get("default_mode")
        chosen = published_mode if album["status"] == "PUBLISHED" else draft_mode
        conflict = bool(
            draft_mode and published_mode and draft_mode != published_mode
        ) or (chosen == "CARDS" and bool(draft.get("cover", {}).get("elements")))
        mode = chosen if chosen in {"BOOK", "CARDS"} and not conflict else "REVIEW"
        modes[aid] = mode
        equal(work.get("mode"), mode, "Work mode changed: " + aid)
        equal(work.get("user_id"), album["user_id"], "Work owner changed: " + aid)
        equal(work.get("request_id"), None, "Unexpected migration request ID: " + aid)
        equal(
            work.get("request_fingerprint"),
            None,
            "Unexpected migration request fingerprint: " + aid,
        )
        converted = convert(draft, mode) if mode != "REVIEW" else draft
        equal(
            work.get("instances"),
            converted["card_instances"],
            "Card instance IDs/order/content changed: " + aid,
        )
        # migrate_materials performs a second backfill with the new work mode.
        # REVIEW may now hydrate a designed cover skipped by an old CARDS draft.
        current_draft = deepcopy(converted)
        current_draft["work_mode"] = mode
        hydrate_document(current_draft, resources)
        used.update(references(current_draft))
        expected_album = deepcopy(album)
        expected_album.update(
            publication_blocked=False,
            moderation_status="RESTRICTED" if album["is_moderated"] else "NORMAL",
            moderation_reason="",
            moderation_note="",
        )
        expected_album["cover_config"] = current_draft["cover"]
        expected_album["card_view_config"] = current_draft["card_view"]
        expected_album["published_snapshot"] = (
            remap(convert(published, mode) if mode != "REVIEW" else published)
            if published
            else album["published_snapshot"]
        )
        equal(
            current_albums.get(aid),
            expected_album,
            "Album fields/rendering/publication changed: " + aid,
        )
        for review in reviews:
            expected = deepcopy(review)
            expected["snapshot"] = remap(
                convert(archived_reviews[review["id"]], mode)
                if mode != "REVIEW"
                else archived_reviews[review["id"]]
            )
            expected_reviews.append(expected)
        if mode != "CARDS":
            for page in pages:
                expected = deepcopy(page)
                config = next(
                    p["config"] for p in draft["pages"] if p["id"] == page["id"]
                )
                expected["page_config"] = remap({"pages": [{"config": config}]})[
                    "pages"
                ][0]["config"]
                expected_pages.append(expected)
                expected_slots.extend(
                    s for s in old["digital_album_slots"] if s["page_id"] == page["id"]
                )
            expected_legacy.extend(
                c for c in old["album_cards"] if c["album_id"] == aid
            )
    for table, expected in (
        ("digital_album_pages", expected_pages),
        ("digital_album_slots", expected_slots),
        ("album_cards", expected_legacy),
        ("digital_album_review_requests", expected_reviews),
    ):
        equal(
            indexed(new[table]),
            indexed(expected),
            "Page/slot/review data changed: " + table,
        )

    preferences = indexed(new["digital_album_preferences"], "user_id")
    old_preferences = indexed(old["digital_album_preferences"], "user_id")
    expected_users = set(old_preferences) | (
        {a["user_id"] for a in albums.values()} if "cream-white" in resources else set()
    )
    equal(set(preferences), expected_users, "Shelf preference owner IDs changed")
    for user_id in expected_users:
        previous = old_preferences.get(user_id)
        actual = preferences.get(user_id, {})
        expected = (
            deepcopy(previous)
            if previous
            else {
                "user_id": user_id,
                "shelf_theme": "cream-white",
                "view_mode": "SHELF",
            }
        )
        resource = resources.get(expected["shelf_theme"])
        expected["shelf_snapshot"] = snapshot(resource) if resource else None
        used.add(expected["shelf_theme"])
        if previous and resource:
            expected.pop("updated_at", None)
            if actual.get("updated_at", "") < previous["updated_at"]:
                errors.append("Shelf timestamp moved backwards: " + user_id)
        equal(
            {k: actual.get(k) for k in expected},
            expected,
            "Shelf preference/snapshot changed: " + user_id,
        )

    expected_resources, originals = {}, {}
    actual_resources = indexed(new["digital_album_resources"])
    for row in old["digital_album_resources"]:
        rid = row["id"]
        expected = deepcopy(row)
        expected.update(
            scene="SHELF" if row["kind"] == "SHELF" else "ALBUM_COVER",
            membership="ALL",
            locked_preview=True,
            published_once=True,
            used_once=rid in used,
        )
        expected_resources[rid] = expected
        originals[rid] = {
            "scene": "BOTH",
            "kind": row["kind"],
            "status": row["status"],
            "config": deepcopy(row["config"]),
            "membership": "ALL",
            "published_once": True,
            "used_once": rid in used,
        }
        if rid in mapping:
            clone = deepcopy(expected)
            clone.update(
                id=mapping[rid],
                scene="ALBUM_PAGE",
                status="OFFLINE" if row["kind"] == "STICKER" else row["status"],
            )
            clone.pop("created_at", None)
            clone.pop("updated_at", None)
            expected_resources[clone["id"]] = clone
    equal(set(actual_resources), set(expected_resources), "Material IDs/clones changed")
    for rid, expected in expected_resources.items():
        equal(
            {key: actual_resources.get(rid, {}).get(key) for key in expected},
            expected,
            "Material content/lifecycle changed: " + rid,
        )
    expected_settings = indexed(old["digital_album_settings"])
    actual_settings = indexed(new["digital_album_settings"])
    if originals:
        expected_settings["v11-material-migration"] = {
            "id": "v11-material-migration",
            "config": {"originals": originals, "page_mapping": mapping},
        }
    equal(set(actual_settings), set(expected_settings), "Album settings IDs changed")
    for key, expected in expected_settings.items():
        equal(
            {field: actual_settings.get(key, {}).get(field) for field in expected},
            expected,
            "Album settings/material archive changed: " + key,
        )
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["snapshot", "compare"])
    parser.add_argument("baseline", nargs="?")
    args = parser.parse_args()
    current = inventory()
    if args.command == "snapshot":
        print(json.dumps(current, sort_keys=True, default=str))
        return
    if not args.baseline:
        parser.error("compare requires the pre-migration baseline file")
    with open(args.baseline) as file:
        before = json.load(file)
    errors = compare(before, current)
    print(
        json.dumps(
            {
                "ok": not errors,
                "protected_tables": len(before["protected"]),
                "albums": len(current["changing"]["card_albums"]),
                "modes": dict(
                    Counter(
                        row["mode"]
                        for row in current["changing"]["digital_album_works"]
                    )
                ),
                "errors": errors,
            },
            ensure_ascii=False,
        )
    )
    raise SystemExit(bool(errors))


if __name__ == "__main__":
    main()
