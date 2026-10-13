"""Album titles remain independent of versions; keep legacy version lists in sync."""

import unicodedata

from sqlalchemy import select

from app.common.response import DomainError
from app.models import Card, CatalogAlbum

from .catalog_extensions import CatalogRecord, records


def version_key(name):
    return unicodedata.normalize("NFKC", name.strip()).casefold()


def album_records(db, album_id):
    return [r for r in records(db, "versions", album_id) if r.entity_type == "albums"]


def album_names(db, album):
    names, seen = [], set()
    for name in [*(album.versions or []), *(r.data["name"] for r in album_records(db, album.id))]:
        if version_key(name) not in seen:
            names.append(name)
            seen.add(version_key(name))
    return names


def set_names(db, album, names):
    from .catalog_service import meta_for

    album.versions = names
    meta = meta_for(db, "albums", album.id)
    if meta:
        meta.data = {**meta.data, "versions": names}


def ensure_versions(db, actor, album, names):
    """Append or materialize known names; existing IDs, images and codes are untouched."""
    from .catalog_service import audit, row_data

    existing = {version_key(r.data["name"]): r for r in album_records(db, album.id)}
    created = []
    for name in names:
        if version_key(name) not in existing:
            record = CatalogRecord(
                kind="versions",
                entity_type="albums",
                entity_id=album.id,
                data={"name": name.strip(), "code": ""},
            )
            db.add(record)
            db.flush()
            existing[version_key(name)] = record
            created.append(record.id)
            audit(db, actor, "catalog.versions.save", "versions", record.id, None, row_data(record))
    set_names(db, album, album_names(db, album))
    return [existing[version_key(name)].id for name in names], created


def referenced(db, record_id):
    from app.admin_models import ContentMetadata

    from .catalog_service import _contains_reference

    return (
        any(_contains_reference(c.admin_data, record_id) for c in db.scalars(select(Card)))
        or any(
            r.id != record_id and _contains_reference(r.data, record_id)
            for r in db.scalars(select(CatalogRecord))
        )
        or any(_contains_reference(m.data, record_id) for m in db.scalars(select(ContentMetadata)))
    )


def replace_versions(db, actor, album, names):
    from .catalog_service import audit, fail_fields, row_data

    selected = {version_key(n) for n in names}
    for record in album_records(db, album.id):
        if version_key(record.data["name"]) not in selected:
            if referenced(db, record.id):
                fail_fields(
                    [
                        {
                            "field": "versions",
                            "message": f"版本 {record.data['name']} 仍有关联，不能移除",
                        }
                    ]
                )
            audit(
                db, actor, "catalog.versions.delete", "versions", record.id, row_data(record), None
            )
            db.delete(record)
    db.flush()
    set_names(db, album, names)
    ensure_versions(db, actor, album, names)


def validate_record_name(db, payload, record_id=None):
    name = str(payload.data.get("name", "")).strip()
    if not name or len(name) > 120:
        raise DomainError("INVALID_VERSION_NAME", "版本名称须为 1–120 字符", 422)
    if any(
        r.id != record_id and version_key(r.data["name"]) == version_key(name)
        for r in album_records(db, payload.entity_id)
    ):
        raise DomainError("VERSION_EXISTS", "该专辑已存在同名版本", 409)
    payload.data = {**payload.data, "name": name}


def sync_after_record(db, entity_id, old_name=None):
    album = db.get(CatalogAlbum, entity_id)
    if not album:
        return
    names = [
        n
        for n in album.versions or []
        if old_name is None or version_key(n) != version_key(old_name)
    ]
    # Flush edits/deletions before deriving the authoritative structural records.
    db.flush()
    existing_keys = {version_key(n) for n in names}
    for record in album_records(db, album.id):
        if version_key(record.data["name"]) not in existing_keys:
            names.append(record.data["name"])
            existing_keys.add(version_key(record.data["name"]))
    set_names(db, album, names)
