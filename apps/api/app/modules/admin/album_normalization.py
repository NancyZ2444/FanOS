"""Explicitly approved 2026-10-11 album families; preserve original IDs and snapshots."""

import copy
import json
from types import SimpleNamespace

from sqlalchemy import inspect, select

from app.models import CatalogAlbum

from .album_versions import album_records, set_names, version_key
from .catalog_extensions import CatalogRecord
from .catalog_service import _contains_reference, audit, meta_for, row_data

NORMALIZATION = "album-versions-20261011"
# Only these exact, human-confirmed draft rows may be split/merged. No title guessing.
FAMILIES = [
    {
        "name": "17 IS RIGHT HERE",
        "parent_id": "album_8ff635b4c4834cc1892ae648cc6fc420",
        "sources": [
            ("album_8ff635b4c4834cc1892ae648cc6fc420", "Standard Ver. A"),
            ("album_48ec7475c4344244add4500754486f2c", "Standard Ver. B"),
            ("album_d5eb01b0f2384b598f0cc5463dcacf67", "DEAR Ver."),
            ("album_423e815e94f14970bf167b2f35a61458", "Deluxe Ver."),
            ("album_508038b43f1749fd84bb40e9b5aa073f", "Kit Ver."),
            ("album_c6d0b0e92e084e3592899a293b3672c6", "Weverse Albums Ver."),
        ],
    },
    {
        "name": "LATATA",
        "parent_id": "album_9d01795869b04155a46b68683847eb0b",
        "sources": [
            ("album_9d01795869b04155a46b68683847eb0b", "通常盤"),
            ("album_b619dee974e7469aa80e75066173eab0", "初回限定盤A"),
            ("album_ac7debe512a44571ba68e5cd076e1331", "初回限定盤B"),
        ],
    },
    {
        "name": "Oh my god",
        "parent_id": "album_027ae8930f3a455db0b5f81ef774714c",
        "sources": [
            ("album_027ae8930f3a455db0b5f81ef774714c", "通常盤"),
            ("album_8feb190926334be1b2c809c5ff989ee8", "初回限定盤A"),
            ("album_ec4b333452cb4b85be3cb4291a87789b", "初回限定盤B"),
        ],
    },
    {
        "name": "THIS MAN",
        "parent_id": "album_bdc008d7975048418424cd16a71e0637",
        "sources": [
            ("album_bdc008d7975048418424cd16a71e0637", "Standard Ver."),
            ("album_5a747f3649c34a9687f2bd0d19db7503", "Weverse Albums Ver."),
        ],
    },
]
LEGACY_ALBUM_IDS = ["album-afterglow", "album-bloom", "album-blue-hour", "album-starlit"]


def artists_key(row, meta):
    artists = meta.data.get("artists") or [{"type": "groups", "id": row.group_id}]
    return sorted((a["type"], a["id"]) for a in artists)


def external_references(db, source_ids):
    """Recheck every table, including JSON, but leave immutable import/audit evidence alone."""
    found = []
    for table in inspect(db.connection()).get_table_names():
        if table in {"catalog_albums", "operation_logs", "admin_import_tasks"}:
            continue
        for raw in db.connection().exec_driver_sql(f'SELECT * FROM "{table}"').mappings():
            if (
                table == "admin_content_metadata"
                and raw["entity_type"] == "albums"
                and raw["entity_id"] in source_ids
            ):
                continue
            for column, value in raw.items():
                if isinstance(value, str) and value.startswith(("{", "[")):
                    try:
                        value = json.loads(value)
                    except ValueError:
                        pass
                for source_id in source_ids:
                    if _contains_reference(value, source_id):
                        found.append(
                            {
                                "table": table,
                                "id": raw.get("id"),
                                "column": column,
                                "source_id": source_id,
                            }
                        )
    return found


def normalize_albums(db, *, apply=False, families=None, legacy_ids=None):
    families = FAMILIES if families is None else families
    legacy_ids = LEGACY_ALBUM_IDS if legacy_ids is None else legacy_ids
    actor = SimpleNamespace(id="system:album-normalization")
    report = {
        "applied": apply,
        "normalization": NORMALIZATION,
        "families": [],
        "mappings": [],
        "versions_created": [],
        "legacy_versions_created": [],
        "touched_album_ids": [],
        "touched_metadata_ids": [],
    }
    pending = []
    # Validate the entire plan before applying any mutation.
    for family in families:
        parent = db.get(CatalogAlbum, family["parent_id"])
        meta = meta_for(db, "albums", family["parent_id"])
        if not parent or not meta:
            raise ValueError(f"Missing approved album: {family['parent_id']}")
        completed = meta.data.get("album_normalization")
        if completed and completed.get("id") == NORMALIZATION:
            mappings = completed["mappings"]
            if len(mappings) != len(family["sources"]):
                raise ValueError("Incomplete historical mapping")
            for mapping in mappings:
                record = db.get(CatalogRecord, mapping["version_id"])
                source_meta = meta_for(db, "albums", mapping["old_id"])
                if not record or record.entity_id != parent.id or not source_meta:
                    raise ValueError("Historical version mapping is missing")
                if mapping["old_id"] != parent.id and (
                    source_meta.status != "ARCHIVED"
                    or source_meta.data.get("merged_into") != parent.id
                    or source_meta.data.get("merged_version_id") != record.id
                ):
                    raise ValueError("Archived ID mapping is inconsistent")
            report["families"].append(
                {"name": family["name"], "parent_id": parent.id, "already_applied": True}
            )
            report["mappings"].extend(mappings)
            continue
        sources = []
        expected_key = (
            parent.group_id,
            parent.release_date,
            parent.album_type,
            artists_key(parent, meta),
        )
        for source_id, version in family["sources"]:
            row = db.get(CatalogAlbum, source_id)
            source_meta = meta_for(db, "albums", source_id)
            expected_name = f"{family['name']} — {version}"
            if not row or not source_meta or row.name != expected_name:
                raise ValueError(f"Approved source title has changed: {source_id}")
            if (
                source_meta.status != "DRAFT"
                or row.is_published
                or source_meta.data.get("ever_published")
            ):
                raise ValueError(f"Approved source is no longer an unpublished draft: {source_id}")
            if (
                row.group_id,
                row.release_date,
                row.album_type,
                artists_key(row, source_meta),
            ) != expected_key:
                raise ValueError(f"Conflicting release attribution: {source_id}")
            if album_records(db, source_id) or row.versions:
                raise ValueError(f"Source already has versions: {source_id}")
            sources.append(
                (
                    row,
                    source_meta,
                    version,
                    copy.deepcopy(row_data(row)),
                    copy.deepcopy(row_data(source_meta)),
                )
            )
        if db.scalar(
            select(CatalogAlbum.id).where(
                CatalogAlbum.name == family["name"], CatalogAlbum.id != parent.id
            )
        ):
            raise ValueError(f"A parent album already exists: {family['name']}")
        refs = external_references(db, {r.id for r, *_ in sources})
        if refs:
            raise ValueError(
                "Approved sources now have business references: "
                + json.dumps(refs, ensure_ascii=False)
            )
        pending.append((family, parent, meta, sources))
    for family, parent, meta, sources in pending:
        mappings = []
        for row, source_meta, version, old_row, old_meta in sources:
            version_id = f"planned:{row.id}"
            if apply:
                record = CatalogRecord(
                    kind="versions",
                    entity_type="albums",
                    entity_id=parent.id,
                    status="DRAFT",
                    data={
                        "name": version,
                        "code": "",
                        "original_album_id": row.id,
                        "original_name": old_row["name"],
                        "normalization": NORMALIZATION,
                        "release_date": row.release_date,
                        "image_url": row.image_url or "",
                        "front_image_url": row.front_image_url or "",
                        "back_image_url": row.back_image_url or "",
                        "description": row.description,
                        "source_info": source_meta.data.get("source_info", {}),
                        "original_snapshot": {"album": old_row, "metadata": old_meta},
                    },
                )
                db.add(record)
                db.flush()
                version_id = record.id
                audit(
                    db,
                    actor,
                    "catalog.album.normalize_version",
                    "versions",
                    record.id,
                    None,
                    row_data(record),
                )
            mapping = {
                "old_id": row.id,
                "old_name": old_row["name"],
                "parent_id": parent.id,
                "album_name": family["name"],
                "version_id": version_id,
                "version_name": version,
            }
            mappings.append(mapping)
            report["versions_created"].append(version_id)
            report["touched_album_ids"].append(row.id)
            report["touched_metadata_ids"].append(source_meta.id)
            if apply and row.id != parent.id:
                source_meta.status = "ARCHIVED"
                source_meta.operator_id = actor.id
                source_meta.data = {
                    **source_meta.data,
                    "merged_into": parent.id,
                    "merged_version_id": version_id,
                    "normalization": NORMALIZATION,
                }
                # Keep original title and all source fields on the archived alias.
                audit(
                    db,
                    actor,
                    "catalog.album.archive_mapping",
                    "albums",
                    row.id,
                    old_meta,
                    row_data(source_meta),
                )
        if apply:
            before = row_data(parent)
            old_name = parent.name
            parent.name = family["name"]
            if parent.name_en == old_name:
                parent.name_en = family["name"]
            data = {
                **meta.data,
                "name": family["name"],
                "album_normalization": {"id": NORMALIZATION, "mappings": mappings},
            }
            if data.get("name_en") == old_name:
                data["name_en"] = family["name"]
            meta.data = data
            meta.operator_id = actor.id
            set_names(db, parent, [v for _, v in family["sources"]])
            audit(
                db,
                actor,
                "catalog.album.normalize_parent",
                "albums",
                parent.id,
                before,
                {"album": row_data(parent), "metadata": row_data(meta)},
            )
        report["families"].append(
            {"name": family["name"], "parent_id": parent.id, "already_applied": False}
        )
        report["mappings"].extend(mappings)
    # Materialize only explicit legacy strings; never split other release titles.
    for album_id in legacy_ids:
        album = db.get(CatalogAlbum, album_id)
        if not album:
            continue
        known = {version_key(r.data["name"]) for r in album_records(db, album_id)}
        meta = meta_for(db, "albums", album_id)
        for name in album.versions or []:
            if version_key(name) in known:
                continue
            record_id = f"planned:{album_id}:{name}"
            if apply:
                record = CatalogRecord(
                    kind="versions",
                    entity_type="albums",
                    entity_id=album_id,
                    status=meta.status
                    if meta
                    else ("PUBLISHED" if album.is_published else "DRAFT"),
                    data={
                        "name": name,
                        "code": "",
                        "normalization": NORMALIZATION,
                        "original_album_id": album_id,
                        "source": "legacy_version_list",
                    },
                )
                db.add(record)
                db.flush()
                record_id = record.id
                audit(
                    db,
                    actor,
                    "catalog.album.materialize_version",
                    "versions",
                    record.id,
                    None,
                    row_data(record),
                )
            report["legacy_versions_created"].append(record_id)
            known.add(version_key(name))
    db.flush() if apply else None
    return report
