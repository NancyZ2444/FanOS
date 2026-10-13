"""Idempotent data backfill for the 2026-10-11 taxonomy migration."""

from sqlalchemy import select

from app.admin_models import CatalogCollection, ContentMetadata
from app.models import Card, CatalogMerchandise, ScanFeedback
from app.modules.admin.catalog_extensions import CatalogRecord

from .tags import TAG_TYPES, bind_tags
from .taxonomy_models import CatalogOther


def canonical_refs(value):
    if isinstance(value, list):
        return [canonical_refs(v) for v in value]
    if not isinstance(value, dict):
        return value
    result = {}
    for key, child in value.items():
        if key in {"source_entity_type", "entity_type", "type", "kind"} and isinstance(child, str):
            child = {
                "COLLECTION": "OTHER",
                "MERCHANDISE": "OTHER",
                "collections": "others",
                "merchandise": "others",
            }.get(child, child)
        result[key] = canonical_refs(child)
    return result


def migrate_taxonomy(db):
    marker_id = "taxonomy-20261011"
    if db.get(CatalogRecord, marker_id):
        return {"others_created": 0, "card_sources_updated": 0, "tagged_entities": 0}
    counts = {"others_created": 0, "card_sources_updated": 0, "tagged_entities": 0}
    for kind, model in [("collections", CatalogCollection), ("merchandise", CatalogMerchandise)]:
        for row in db.scalars(select(model)).all():
            existing = db.get(CatalogOther, row.id)
            if existing:
                if (existing.legacy_data or {}).get("legacy_kind") != kind:
                    raise RuntimeError(f"Other ID collision: {row.id}; no records were overwritten")
                continue
            meta = db.scalar(
                select(ContentMetadata).where(
                    ContentMetadata.entity_type == kind, ContentMetadata.entity_id == row.id
                )
            )
            data = dict(meta.data or {}) if meta else {}
            legacy = {
                c.name: (
                    getattr(row, c.name).isoformat()
                    if hasattr(getattr(row, c.name), "isoformat")
                    else getattr(row, c.name)
                )
                for c in model.__table__.columns
            }
            original = (
                data.get("original_name")
                or data.get("name_en")
                or data.get("name_ko")
                or getattr(row, "name_en", "")
                or getattr(row, "name_ko", "")
                or ""
            )
            db.add(
                CatalogOther(
                    id=row.id,
                    name=row.name,
                    original_name=original,
                    start_date=getattr(row, "release_date", "").replace(".", "-"),
                    end_date=data.get("end_date", ""),
                    description=row.description,
                    group_id=row.group_id,
                    is_published=(
                        meta.status == "PUBLISHED" if meta else getattr(row, "is_published", True)
                    ),
                    legacy_data={**legacy, "legacy_kind": kind, "metadata": data},
                    created_at=row.created_at,
                    updated_at=row.updated_at,
                )
            )
            if meta:
                meta.entity_type = "others"
                meta.data = {
                    **data,
                    "name": row.name,
                    "original_name": original,
                    "start_date": getattr(row, "release_date", "").replace(".", "-"),
                    "legacy_source_type": kind,
                }
            else:
                db.add(
                    ContentMetadata(
                        entity_type="others",
                        entity_id=row.id,
                        status="PUBLISHED" if getattr(row, "is_published", True) else "DRAFT",
                        operator_id="legacy",
                        data={"tags": [], "legacy_source_type": kind},
                    )
                )
            row.group_id = None  # Ownership survives on Other and in the legacy snapshot.
            counts["others_created"] += 1
    db.flush()
    for card in db.scalars(select(Card)).all():
        data = card.admin_data or {}
        if data.get("source_entity_type") in {"COLLECTION", "MERCHANDISE"}:
            card.admin_data = {
                **data,
                "legacy_source_entity_type": data["source_entity_type"],
                "source_entity_type": "OTHER",
            }
            counts["card_sources_updated"] += 1
    for row in db.scalars(select(CatalogRecord)).all():
        if row.kind == "import_input":
            continue  # Immutable import history remains available as evidence.
        if row.entity_type in {"collections", "merchandise"}:
            row.entity_type = "others"
        updated = canonical_refs(row.data)
        if updated != row.data:
            row.data = updated
    for row in db.scalars(select(ScanFeedback)).all():
        updated = canonical_refs(row.payload)
        if updated != row.payload:
            row.payload = updated
    db.flush()
    for kind, entity_id, values in [
        *[("cards", c.id, (c.admin_data or {}).get("tags", [])) for c in db.scalars(select(Card))],
        *[
            (m.entity_type, m.entity_id, (m.data or {}).get("tags", []))
            for m in db.scalars(select(ContentMetadata))
            if m.entity_type in TAG_TYPES and m.entity_type != "cards"
        ],
    ]:
        if values:
            # Existing arrays were internal operational attributes. Do not invent
            # provenance for historical user suggestions that were never accepted.
            bind_tags(db, kind, entity_id, values, "legacy")
            counts["tagged_entities"] += 1
    db.flush()
    db.add(CatalogRecord(id=marker_id, kind="taxonomy_migrations", status="COMPLETED", data=counts))
    db.flush()
    return counts
