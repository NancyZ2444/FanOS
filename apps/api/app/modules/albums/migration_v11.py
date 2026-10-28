"""Lossless migration. Ambiguous works stay read-only until explicitly resolved."""

from copy import deepcopy
from hashlib import sha256

from sqlalchemy import delete, select, update

from app.album_models import (
    AlbumPage,
    AlbumResource,
    AlbumReviewRequest,
    AlbumSettings,
    AlbumSlot,
    AlbumWork,
)
from app.models import AlbumCard, CardAlbum


def convert(doc, mode):
    result = deepcopy(doc)
    result["work_mode"] = mode
    view = result.setdefault("card_view", {})
    view["default_mode"] = mode
    if mode == "CARDS":
        slots = [s for p in doc.get("pages", []) for s in p["slots"] if s.get("card_id")]
        by_id = {s["id"]: s for s in slots}
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
    else:
        result["card_instances"] = []
    return result


def migrate_works(db, resolutions=None):
    from . import service

    resolutions = resolutions or {}
    report = []
    for album in db.scalars(select(CardAlbum)).all():
        original_updated = album.updated_at
        work = db.get(AlbumWork, album.id)
        if work and work.mode != "REVIEW":
            continue
        doc = (
            deepcopy(work.migration_archive["draft"])
            if work and work.migration_archive
            else service.document(db, album)
        )
        reviews = db.scalars(
            select(AlbumReviewRequest).where(AlbumReviewRequest.album_id == album.id)
        ).all()
        archive = (
            deepcopy(work.migration_archive)
            if work
            else {
                "draft": doc,
                "published": deepcopy(album.published_snapshot),
                "reviews": {r.id: deepcopy(r.snapshot) for r in reviews},
            }
        )
        draft_mode = doc.get("card_view", {}).get("default_mode")
        published_mode = (archive["published"] or {}).get("card_view", {}).get("default_mode")
        chosen = published_mode if album.status == "PUBLISHED" else draft_mode
        conflict = bool(draft_mode and published_mode and draft_mode != published_mode)
        # A CARDS work with a designed cover needs an explicit choice before archiving it.
        conflict |= chosen == "CARDS" and bool(doc.get("cover", {}).get("elements"))
        mode = resolutions.get(album.id) or (
            chosen if chosen in {"BOOK", "CARDS"} and not conflict else "REVIEW"
        )
        if not work:
            work = AlbumWork(
                album_id=album.id,
                user_id=album.user_id,
                mode=mode,
                instances=[],
                migration_archive=archive,
            )
            db.add(work)
        work.mode = mode
        report.append(
            {
                "id": album.id,
                "name": album.name,
                "mode": mode,
                "requires_confirmation": mode == "REVIEW",
                "cards": sum(
                    bool(s.get("card_id")) for p in doc.get("pages", []) for s in p["slots"]
                ),
            }
        )
        if mode == "REVIEW":
            continue
        converted = convert(doc, mode)
        work.instances = converted["card_instances"]
        album.cover_config, album.card_view_config = converted["cover"], converted["card_view"]
        if archive["published"]:
            album.published_snapshot = convert(archive["published"], mode)
        for review in reviews:
            review.snapshot = convert(archive["reviews"][review.id], mode)
        if mode == "CARDS":
            page_ids = select(AlbumPage.id).where(AlbumPage.album_id == album.id)
            db.execute(delete(AlbumSlot).where(AlbumSlot.page_id.in_(page_ids)))
            db.execute(delete(AlbumPage).where(AlbumPage.album_id == album.id))
            db.execute(delete(AlbumCard).where(AlbumCard.album_id == album.id))
        db.flush()
        db.execute(
            update(CardAlbum).where(CardAlbum.id == album.id).values(updated_at=original_updated)
        )
    db.flush()
    return report


def migrate_materials(db):
    """Split legacy BOTH entries. Do not grant card-scene permissions implicitly."""
    from .materials import backfill_snapshots

    backfill_snapshots(db)
    mapping = {}
    originals = {}
    for row in db.scalars(select(AlbumResource)).all():
        old_scene = row.scene
        if old_scene in {"SHELF", "ALBUM_COVER", "ALBUM_PAGE", "CARD_BACKGROUND"}:
            continue
        originals[row.id] = {
            "scene": old_scene,
            "kind": row.kind,
            "status": row.status,
            "config": deepcopy(row.config),
            "membership": row.membership,
            "published_once": row.published_once,
            "used_once": row.used_once,
        }
        row.scene = (
            "SHELF"
            if row.kind == "SHELF"
            else "ALBUM_PAGE"
            if old_scene == "PAGE"
            else "ALBUM_COVER"
        )
        if row.kind == "STICKER" and row.scene == "ALBUM_PAGE":
            row.status = "OFFLINE" if row.published_once else "DRAFT"
        if old_scene == "BOTH" and row.kind != "SHELF":
            rid = row.id[:40] + "-page-" + sha256(row.id.encode()).hexdigest()[:10]
            clone = AlbumResource(
                id=rid,
                name=row.name,
                kind=row.kind,
                scene="ALBUM_PAGE",
                status="OFFLINE" if row.kind == "STICKER" else row.status,
                config=deepcopy(row.config),
                membership=row.membership,
                locked_preview=row.locked_preview,
                sort_order=row.sort_order,
                published_once=row.published_once,
                used_once=row.used_once,
            )
            db.add(clone)
            mapping[row.id] = rid

    def remap(doc):
        for page in doc.get("pages", []):
            config = page.get("config", {})
            bg = config.get("background", {})
            if bg.get("resource_id") in mapping:
                bg["resource_id"] = mapping[bg["resource_id"]]
            for e in config.get("elements", []):
                if e.get("type") == "STICKER" and e.get("content") in mapping:
                    e["content"] = mapping[e["content"]]
        return doc

    for page in db.scalars(select(AlbumPage)).all():
        page.page_config = remap({"pages": [{"config": deepcopy(page.page_config)}]})["pages"][0][
            "config"
        ]
    for album in db.scalars(select(CardAlbum)).all():
        if album.published_snapshot:
            album.published_snapshot = remap(deepcopy(album.published_snapshot))
    for review in db.scalars(select(AlbumReviewRequest)).all():
        review.snapshot = remap(deepcopy(review.snapshot))
    if originals and not db.get(AlbumSettings, "v11-material-migration"):
        db.add(
            AlbumSettings(
                id="v11-material-migration",
                config={"originals": originals, "page_mapping": mapping},
            )
        )
    db.flush()
    return mapping
