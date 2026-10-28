from __future__ import annotations

from collections import Counter
from copy import deepcopy
from datetime import UTC
from zoneinfo import ZoneInfo

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session, attributes

from app.album_models import (
    AlbumColorExtraction,
    AlbumEntitlement,
    AlbumPage,
    AlbumPreferences,
    AlbumReaction,
    AlbumResource,
    AlbumReviewRequest,
    AlbumSettings,
    AlbumSlot,
    AlbumWork,
)
from app.common.response import DomainError
from app.models import AlbumCard, Card, CardAlbum, User, new_id, utcnow
from app.modules.albums.schemas import AlbumCreate, AlbumLimits, AlbumPatch, CanvasConfig

DEFAULT_RESOURCES = [
    {
        "id": "cream-white",
        "name": "奶油白",
        "kind": "SHELF",
        "config": {"colors": ["#F4EEE7", "#FFFFFF"], "ledge": "#DAD0C5"},
    },
    {
        "id": "soft-pink",
        "name": "浅粉色",
        "kind": "SHELF",
        "config": {"colors": ["#F4DCE5", "#FFF6FA"], "ledge": "#D7B5C3"},
    },
    {
        "id": "natural-wood",
        "name": "浅木色",
        "kind": "SHELF",
        "config": {"colors": ["#D7C7BB", "#F5E6D7"], "ledge": "#C8B5A5"},
    },
    {
        "id": "silver-metal",
        "name": "银色金属",
        "kind": "SHELF",
        "config": {"colors": ["#CDD0DC", "#F5F6FB"], "ledge": "#A9AEBB"},
    },
    {
        "id": "minimal",
        "name": "极简",
        "kind": "SHELF",
        "config": {"colors": ["#F0EDFF", "#FAFAFF"], "ledge": "#DED8F7"},
    },
    *[
        {"id": key, "name": name, "kind": "STICKER", "config": {"symbol": symbol}}
        for key, name, symbol in [
            ("star", "星光", "✦"),
            ("heart", "热爱", "♡"),
            ("bow", "蝴蝶结", "🎀"),
            ("flower", "花朵", "✿"),
            ("stay", "陪伴", "STAY"),
        ]
    ],
    {
        "id": "dream",
        "name": "梦境",
        "kind": "BACKGROUND",
        "config": {"type": "GRADIENT", "colors": ["#D7CEFF", "#F9DEE9"], "angle": 45},
    },
    {
        "id": "ocean",
        "name": "晴空",
        "kind": "BACKGROUND",
        "config": {"type": "GRADIENT", "colors": ["#79CDFF", "#DED2ED"], "angle": 90},
    },
    {
        "id": "night",
        "name": "夜光",
        "kind": "BACKGROUND",
        "config": {"type": "GRADIENT", "colors": ["#E885D6", "#508CE9"], "angle": 90},
    },
]

# Separate entries can share pixels, never scene permissions or lifecycle.
DEFAULT_RESOURCES = [
    {**r, "scene": scene, "id": r["id"] + suffix}
    for r in DEFAULT_RESOURCES
    for scene, suffix in (
        [("SHELF", "")]
        if r["kind"] == "SHELF"
        else [("ALBUM_COVER", "")]
        if r["kind"] == "STICKER"
        else [("ALBUM_COVER", ""), ("ALBUM_PAGE", "-page"), ("CARD_BACKGROUND", "-cards")]
    )
]


def resources(db: Session, *, include_offline=False) -> list[dict]:
    custom = {r.id: r for r in db.scalars(select(AlbumResource)).all()}
    result = []
    for default in DEFAULT_RESOURCES:
        row = custom.pop(default["id"], None)
        result.append(
            resource_payload(row)
            if row
            else {
                **default,
                "status": "PUBLISHED",
                "sort_order": len(result),
                "membership": "ALL",
                "locked_preview": True,
                "published_once": True,
                "used_once": True,
            }
        )
    result.extend(resource_payload(row) for row in custom.values())
    return sorted(
        [r for r in result if include_offline or r["status"] == "PUBLISHED"],
        key=lambda r: r["sort_order"],
    )


def resource_payload(row: AlbumResource) -> dict:
    return {
        "id": row.id,
        "name": row.name,
        "kind": row.kind,
        "status": row.status,
        "sort_order": row.sort_order,
        "config": row.config,
        "scene": row.scene,
        "membership": row.membership,
        "locked_preview": row.locked_preview,
        "published_once": row.published_once,
        "used_once": row.used_once,
        "updated_at": row.updated_at.isoformat(),
    }


def limits(db: Session) -> dict:
    row = db.get(AlbumSettings, "global")
    return AlbumLimits.model_validate(row.config if row else {}).model_dump()


def lock_quota(db: Session, user: User) -> None:
    # A real write lock on SQLite and a row lock on PostgreSQL serializes quota checks.
    db.execute(update(User).where(User.id == user.id).values(updated_at=User.updated_at))


def quota(db: Session, user: User) -> dict:
    entitlement = db.get(AlbumEntitlement, user.id)
    expiry = entitlement.expires_at if entitlement else None
    if expiry and expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=UTC)
    pro = bool(entitlement and entitlement.plan == "PRO" and (not expiry or expiry > utcnow()))
    config = limits(db)
    count = (
        db.scalar(
            select(func.count())
            .select_from(CardAlbum)
            .where(CardAlbum.user_id == user.id, CardAlbum.status != "DELETED")
        )
        or 0
    )
    return {
        "plan": "PRO" if pro else "NORMAL",
        "album_count": count,
        "max_album_count": config["pro_albums" if pro else "normal_albums"],
        "max_page_per_album": config["pro_pages" if pro else "normal_pages"],
        "max_card_per_page": config["max_card_per_page"],
        "max_cards_per_work": config["pro_cards" if pro else "normal_cards"],
        "normal_albums": config["normal_albums"],
        "pro_albums": config["pro_albums"],
        "normal_pages": config["normal_pages"],
        "pro_pages": config["pro_pages"],
        "color_extraction": color_quota(db, user, "PRO" if pro else "NORMAL", config),
    }


def color_quota(db: Session, user: User, plan: str, config: dict) -> dict:
    now = utcnow().astimezone(ZoneInfo("Asia/Shanghai"))
    day = now.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(UTC)
    month = day.astimezone(ZoneInfo("Asia/Shanghai")).replace(day=1).astimezone(UTC)
    counts = [
        db.scalar(
            select(func.count())
            .select_from(AlbumColorExtraction)
            .where(
                AlbumColorExtraction.user_id == user.id, AlbumColorExtraction.created_at >= boundary
            )
        )
        or 0
        for boundary in (day, month)
    ]
    prefix = "pro" if plan == "PRO" else "normal"
    daily, monthly = config[f"{prefix}_color_daily"], config[f"{prefix}_color_monthly"]
    return {
        "daily_limit": daily,
        "monthly_limit": monthly,
        "daily_used": counts[0],
        "monthly_used": counts[1],
        "daily_remaining": max(0, daily - counts[0]),
        "monthly_remaining": max(0, monthly - counts[1]),
        "timezone": "Asia/Shanghai",
    }


def latest_review(db: Session, album_id: str):
    return db.scalar(
        select(AlbumReviewRequest)
        .where(AlbumReviewRequest.album_id == album_id)
        .order_by(AlbumReviewRequest.created_at.desc(), AlbumReviewRequest.id.desc())
        .limit(1)
    )


def moderation_state(album: CardAlbum):
    return (
        album.moderation_status
        if album.is_moderated and album.moderation_status != "NORMAL"
        else "RESTRICTED"
        if album.is_moderated
        else "NORMAL"
    )


def preferences(db: Session, user: User) -> dict:
    from .materials import catalog, snapshot

    row = db.get(AlbumPreferences, user.id)
    resource = catalog(db).get(row.shelf_theme if row else "cream-white")
    return {
        "shelf_theme": row.shelf_theme if row else "cream-white",
        "view_mode": row.view_mode if row else "SHELF",
        "shelf_snapshot": row.shelf_snapshot
        if row and row.shelf_snapshot
        else snapshot(resource)
        if resource
        else None,
    }


def get_album(db: Session, album_id: str, viewer: User | None, *, edit=False) -> CardAlbum:
    row = db.get(CardAlbum, album_id)
    if not row or row.status == "DELETED":
        raise DomainError("ALBUM_NOT_FOUND", "相册不存在或已删除", 404)
    is_owner = viewer is not None and row.user_id == viewer.id
    author = db.get(User, row.user_id)
    if not is_owner and (not author or not author.is_active):
        raise DomainError("ALBUM_UNAVAILABLE", "作者账号暂不可访问", 403)
    if edit and not is_owner:
        raise DomainError("ALBUM_FORBIDDEN", "只有创建者可以编辑相册", 403)
    work = db.get(AlbumWork, album_id)
    if edit and work and work.mode == "REVIEW":
        raise DomainError("ALBUM_MIGRATION_REVIEW", "旧作品类型待确认，原设计已归档保留", 409)
    if not is_owner and (
        not row.is_public
        or row.status != "PUBLISHED"
        or row.is_moderated
        or row.publication_blocked
    ):
        raise DomainError("ALBUM_UNAVAILABLE", "相册为私密、未发布或暂不可访问", 403)
    return row


def document(db: Session, album: CardAlbum) -> dict:
    work = db.get(AlbumWork, album.id)
    pages = []
    rows = db.scalars(
        select(AlbumPage).where(AlbumPage.album_id == album.id).order_by(AlbumPage.page_order)
    ).all()
    slots = (
        db.scalars(
            select(AlbumSlot)
            .where(AlbumSlot.page_id.in_([p.id for p in rows]))
            .order_by(AlbumSlot.slot_order)
        ).all()
        if rows
        else []
    )
    for page in rows:
        pages.append(
            {
                "id": page.id,
                "grid_count": page.grid_count,
                "config": deepcopy(page.page_config),
                "slots": [
                    {"id": s.id, "card_id": s.card_id} for s in slots if s.page_id == page.id
                ],
            }
        )
    if not rows:
        # Legacy books are read without mutation; their stable placement IDs survive first save.
        legacy = db.scalars(
            select(AlbumCard).where(AlbumCard.album_id == album.id).order_by(AlbumCard.sort_order)
        ).all()
        for index in range(0, len(legacy), 9):
            chunk = legacy[index : index + 9]
            pages.append(
                {
                    "id": f"legacy-{album.id[:45]}-{index // 9}",
                    "grid_count": len(chunk),
                    "config": CanvasConfig().model_dump(),
                    "slots": [{"id": row.id, "card_id": row.card_id} for row in chunk],
                }
            )
    mode = work.mode if work else (album.card_view_config or {}).get("default_mode", "BOOK")
    return {
        "album_id": album.id,
        "work_mode": mode,
        "card_instances": deepcopy(work.instances) if work and mode == "CARDS" else [],
        "name": album.name,
        "description": album.description,
        "display_type": album.display_type,
        "visual_style": album.visual_style,
        "cover": {}
        if work and mode == "CARDS"
        else deepcopy(album.cover_config) or CanvasConfig().model_dump(),
        "card_view": deepcopy(album.card_view_config),
        "pages": [] if work and mode == "CARDS" else pages,
    }


def occupied(doc: dict) -> list[dict]:
    if doc.get("work_mode") == "CARDS":
        return doc.get("card_instances", [])
    return [s for p in doc["pages"] for s in p["slots"] if s.get("card_id")]


def sync_card_view(doc: dict) -> None:
    slot_ids = [s["id"] for s in occupied(doc)]
    view = doc["card_view"]
    if view.get("order_customized"):
        order = list(dict.fromkeys(s for s in view.get("card_order", []) if s in slot_ids))
        view["card_order"] = order + [s for s in slot_ids if s not in order]
    else:
        view["card_order"] = slot_ids
    if view.get("featured_slot_id") not in slot_ids:
        view["featured_slot_id"] = (
            view["card_order"][0] if slot_ids and doc.get("work_mode") == "CARDS" else None
        )
    view["default_mode"] = doc.get("work_mode", view.get("default_mode", "BOOK"))
    view.setdefault(
        "background", {"type": "GRADIENT", "colors": ["#F4F1FF", "#E5DEFA"], "angle": 90}
    )
    view.setdefault("order_customized", False)
    view.setdefault("animation_style", "STACK")


def card_available(card: Card | None) -> bool:
    if not card or card.status != "PUBLISHED":
        return False
    data = card.admin_data or {}
    forbidden = {"REVOKED", "UNAUTHORIZED", "EXPIRED", "FORBIDDEN", "OFFLINE", "REJECTED"}
    return data.get("front_source", {}).get("copyright_status", "UNKNOWN") not in forbidden


def payload(
    db: Session,
    album: CardAlbum,
    viewer: User | None,
    *,
    summary=False,
    published=False,
    document_override=None,
) -> dict:
    from app.common.serializers import card_payload

    owner = viewer is not None and viewer.id == album.user_id
    doc = (
        deepcopy(album.published_snapshot)
        if (published or not owner) and album.published_snapshot
        else document(db, album)
    )
    from .materials import catalog, hydrate_document

    if document_override is not None:
        doc = deepcopy(document_override)
    hydrate_document(doc, catalog(db))
    sync_card_view(doc)
    # Featured front, then ordered fronts. Preserve slot identity and availability.
    slots_by_id = {s["id"]: s for s in occupied(doc)}
    ordered = [slots_by_id[s] for s in doc["card_view"]["card_order"]]
    featured = doc["card_view"].get("featured_slot_id")
    cover_slots = (
        [s for s in ordered if s["id"] == featured] + [s for s in ordered if s["id"] != featured]
    )[:5]
    # Shelf responses need at most five cover cards, not all 450 inner-page assets.
    card_ids = set() if summary else {s["card_id"] for s in occupied(doc)}
    card_ids.update(s["card_id"] for s in cover_slots)
    card_ids.update(e["content"] for e in doc["cover"].get("elements", []) if e["type"] == "CARD")
    cards = {}
    for card in db.scalars(select(Card).where(Card.id.in_(card_ids))).all():
        cards[card.id] = (
            card_payload(db, card)
            if card_available(card)
            else {"id": card.id, "available": False, "title": "小卡暂不可用"}
        )
        if cards[card.id].get("available") is not False:
            cards[card.id]["available"] = True
            # A revoked back image must not leak through the front-card preview.
            if (card.admin_data or {}).get("back_source", {}).get("copyright_status") in {
                "REVOKED",
                "UNAUTHORIZED",
                "EXPIRED",
                "FORBIDDEN",
                "OFFLINE",
                "REJECTED",
            }:
                cards[card.id]["back_image_url"] = None
    for card_id in card_ids - cards.keys():
        cards[card_id] = {"id": card_id, "available": False, "title": "小卡暂不可用"}
    author = db.get(User, album.user_id)
    counts = {
        kind: db.scalar(
            select(func.count())
            .select_from(AlbumReaction)
            .where(AlbumReaction.album_id == album.id, AlbumReaction.kind == kind)
        )
        or 0
        for kind in ("LIKE", "FAVORITE")
    }
    mine = (
        set(
            db.scalars(
                select(AlbumReaction.kind).where(
                    AlbumReaction.album_id == album.id, AlbumReaction.user_id == viewer.id
                )
            ).all()
        )
        if viewer
        else set()
    )
    review = latest_review(db, album.id)
    review_status = review.status if review and owner else "NONE"
    if review_status == "RESTORED" and album.published_at:
        published_time = (
            album.published_at.replace(tzinfo=UTC)
            if album.published_at.tzinfo is None
            else album.published_at
        )
        reviewed_time = (
            review.updated_at.replace(tzinfo=UTC)
            if review.updated_at.tzinfo is None
            else review.updated_at
        )
        if published_time >= reviewed_time:
            review_status = "NONE"
    if owner and album.publication_blocked and not album.is_moderated:
        review_status = "RESTORED"
    result = {
        "id": album.id,
        "work_mode": doc.get("work_mode", "BOOK"),
        "user_id": album.user_id,
        "author_name": author.display_name if author else "用户",
        "author_avatar_url": author.avatar_url if author else None,
        "is_owner": owner,
        "name": doc["name"],
        "description": doc["description"],
        "display_type": doc["display_type"],
        "visual_style": doc["visual_style"],
        "visibility": "PUBLIC" if album.is_public else "PRIVATE",
        "status": album.status,
        "revision": album.revision if owner else None,
        "is_moderated": album.is_moderated,
        "publication_blocked": album.publication_blocked,
        "moderation_status": moderation_state(album),
        "moderation_reason": album.moderation_reason if owner else "",
        "moderation_note": album.moderation_note if owner else "",
        "review_status": review_status,
        "published_at": album.published_at.isoformat() if album.published_at else None,
        "page_count": len(doc["pages"]),
        "card_count": len(occupied(doc)),
        "cover": doc["cover"],
        "cover_slots": cover_slots,
        "card_view": (
            {k: v for k, v in doc["card_view"].items() if k != "card_order"}
            if summary
            else doc["card_view"]
        ),
        "cards": cards,
        "color_start": album.color_start,
        "color_end": album.color_end,
        "is_public": album.is_public,
        "updated_label": "最近更新",
        "created_at": album.created_at.isoformat(),
        "updated_at": album.updated_at.isoformat(),
        "like_count": counts["LIKE"],
        "favorite_count": counts["FAVORITE"],
        "liked": "LIKE" in mine,
        "favorited": "FAVORITE" in mine,
    }
    if not summary:
        result.update(
            pages=doc["pages"],
            card_view=doc["card_view"],
            card_instances=doc.get("card_instances", []),
        )
    return result


def create(db: Session, user: User, data: AlbumCreate) -> CardAlbum:
    import hashlib
    import json

    lock_quota(db, user)
    fingerprint = hashlib.sha256(
        json.dumps(data.model_dump(exclude={"request_id"}), sort_keys=True).encode()
    ).hexdigest()
    if data.request_id:
        existing = db.scalar(
            select(AlbumWork).where(
                AlbumWork.user_id == user.id, AlbumWork.request_id == data.request_id
            )
        )
        if existing:
            if existing.request_fingerprint != fingerprint:
                raise DomainError(
                    "ALBUM_CREATE_CONFLICT", "此创建请求已用于另一份作品，请重新创建", 409
                )
            return db.get(CardAlbum, existing.album_id)
    capacity = quota(db, user)
    if capacity["album_count"] >= capacity["max_album_count"]:
        raise DomainError(
            "ALBUM_QUOTA_EXCEEDED", f"相册数量已达 {capacity['max_album_count']} 本上限", 409
        )
    if not data.name.strip():
        raise DomainError("INVALID_ALBUM_NAME", "请填写相册名称", 422)
    album = CardAlbum(
        user_id=user.id,
        name=data.name.strip(),
        description=data.description,
        display_type=data.display_type or "SINGLE",
        visual_style=data.visual_style or "REALISTIC",
        is_public=False,
        status="DRAFT",
        cover_config=CanvasConfig().model_dump() if data.work_mode == "BOOK" else {},
        card_view_config={"default_mode": data.work_mode},
    )
    db.add(album)
    db.flush()
    db.add(
        AlbumWork(
            album_id=album.id,
            user_id=user.id,
            mode=data.work_mode,
            instances=[],
            request_id=data.request_id,
            request_fingerprint=fingerprint,
        )
    )
    db.flush()
    return album


def claim(db: Session, album: CardAlbum, revision: int) -> None:
    changed = db.execute(
        update(CardAlbum)
        .where(
            CardAlbum.id == album.id, CardAlbum.revision == revision, CardAlbum.status != "DELETED"
        )
        .values(revision=revision + 1, updated_at=utcnow())
        .execution_options(synchronize_session=False)
    )
    if changed.rowcount != 1:
        db.rollback()
        raise DomainError(
            "ALBUM_REVISION_CONFLICT", "相册已在其他设备更新，请重新加载；本地草稿不会被覆盖", 409
        )
    attributes.set_committed_value(album, "revision", revision + 1)


def validate_document(db: Session, user: User, previous: dict, doc: dict, data: AlbumPatch) -> None:
    from .work_types import validate_work

    validate_work(db, user, previous, doc, data)
    config = quota(db, user)
    if not doc["name"].strip():
        raise DomainError("INVALID_ALBUM_NAME", "请填写相册名称", 422)
    if len(doc["pages"]) > config["max_page_per_album"] and len(doc["pages"]) > len(
        previous["pages"]
    ):
        raise DomainError(
            "ALBUM_PAGE_QUOTA_EXCEEDED",
            f"当前相册已达到 {config['max_page_per_album']} 页上限",
            409,
        )
    page_ids = [p["id"] for p in doc["pages"]]
    slots = (
        doc.get("card_instances", [])
        if doc.get("work_mode") == "CARDS"
        else [s for p in doc["pages"] for s in p["slots"]]
    )
    if len(set(page_ids)) != len(page_ids) or len({s["id"] for s in slots}) != len(slots):
        raise DomainError("ALBUM_INVALID_IDS", "页面和卡位 ID 必须唯一", 422)
    old_pages = {p["id"]: p for p in previous["pages"]}
    old_slots = {
        s["id"]: s
        for s in (
            previous.get("card_instances", [])
            if previous.get("work_mode") == "CARDS"
            else [s for p in previous["pages"] for s in p["slots"]]
        )
    }
    for page in doc["pages"]:
        existing = db.get(AlbumPage, page["id"])
        if existing and existing.album_id != previous["album_id"]:
            raise DomainError("ALBUM_INVALID_IDS", "页面不属于当前相册", 422)
        if page["grid_count"] > config["max_card_per_page"] and page["grid_count"] > old_pages.get(
            page["id"], {}
        ).get("grid_count", 0):
            raise DomainError("ALBUM_SLOT_QUOTA_EXCEEDED", "卡位数量超过当前布局上限", 409)
    for slot in slots:
        if db.get(AlbumSlot, slot["id"]) and slot["id"] not in old_slots:
            raise DomainError("ALBUM_INVALID_IDS", "卡位不属于当前相册", 422)
        if slot.get("card_id") and old_slots.get(slot["id"], {}).get("card_id") != slot["card_id"]:
            if not card_available(db.get(Card, slot["card_id"])):
                raise DomainError("ALBUM_CARD_UNAVAILABLE", "只能添加当前可用的官方图鉴小卡", 422)
    elements = doc["cover"].get("elements", [])
    cover_cards = [e["content"] for e in elements if e["type"] == "CARD"]
    if len(cover_cards) > 1:
        raise DomainError("ALBUM_COVER_CARD_LIMIT", "封面最多放置一张小卡", 422)
    old_cover = {e["content"] for e in previous["cover"].get("elements", []) if e["type"] == "CARD"}
    for card_id in cover_cards:
        if card_id not in old_cover and not card_available(db.get(Card, card_id)):
            raise DomainError("ALBUM_CARD_UNAVAILABLE", "封面小卡暂不可用", 422)
    from .materials import validate_materials

    validate_materials(db, user, previous, doc)
    # Removing a populated slot or an entire page must be explicitly confirmed.
    if not data.confirm_removal:
        if set(old_pages) - set(page_ids) or any(
            s["card_id"] and s["id"] not in {x["id"] for x in slots} for s in old_slots.values()
        ):
            raise DomainError(
                "ALBUM_REMOVAL_CONFIRM_REQUIRED", "请确认移除页面或超出布局的小卡", 409
            )
    counts = Counter(s["card_id"] for s in slots if s["card_id"])
    previous_counts = Counter(s["card_id"] for s in old_slots.values() if s["card_id"])
    if not data.confirm_duplicates and any(
        count > 1 and count > previous_counts[card_id] for card_id, count in counts.items()
    ):
        raise DomainError(
            "ALBUM_DUPLICATE_CONFIRM_REQUIRED", "该小卡已在本相册中，请确认继续添加", 409
        )


def persist_pages(db: Session, album: CardAlbum, pages: list[dict]) -> None:
    old_page_ids = list(
        db.scalars(select(AlbumPage.id).where(AlbumPage.album_id == album.id)).all()
    )
    page_ids = [p["id"] for p in pages]
    slot_ids = [s["id"] for p in pages for s in p["slots"]]
    if old_page_ids:
        db.execute(
            delete(AlbumSlot).where(
                AlbumSlot.page_id.in_(old_page_ids), AlbumSlot.id.not_in(slot_ids)
            )
        )
    for order, data in enumerate(pages):
        page = db.get(AlbumPage, data["id"])
        if page is None:
            page = AlbumPage(id=data["id"], album_id=album.id)
            db.add(page)
        page.page_order, page.grid_count, page.page_config = (
            order,
            data["grid_count"],
            data["config"],
        )
        db.flush()
        for index, data_slot in enumerate(data["slots"]):
            slot = db.get(AlbumSlot, data_slot["id"])
            if slot is None:
                slot = AlbumSlot(id=data_slot["id"])
                db.add(slot)
            slot.page_id, slot.slot_order, slot.card_id = page.id, index, data_slot["card_id"]
        db.flush()
    db.execute(
        delete(AlbumPage).where(AlbumPage.album_id == album.id, AlbumPage.id.not_in(page_ids))
    )
    db.execute(delete(AlbumCard).where(AlbumCard.album_id == album.id))


def patch(db: Session, album: CardAlbum, user: User, data: AlbumPatch) -> CardAlbum:
    lock_quota(db, user)
    db.refresh(album)
    if album.revision != data.revision:
        raise DomainError("ALBUM_REVISION_CONFLICT", "相册已更新，请重新加载；本地草稿会保留", 409)
    previous = document(db, album)
    doc = deepcopy(previous)
    for key in (
        "name",
        "description",
        "display_type",
        "visual_style",
        "cover",
        "card_view",
        "pages",
        "card_instances",
    ):
        value = getattr(data, key)
        if value is not None:
            doc[key] = (
                value.model_dump()
                if hasattr(value, "model_dump")
                else [p.model_dump() for p in value]
                if key in {"pages", "card_instances"}
                else value
            )
    validate_document(db, user, previous, doc, data)
    if data.visibility == "PUBLIC" and not album.is_public and album.status == "PUBLISHED":
        validate_publication(db, album, album.published_snapshot or previous)
    # Reject invalid references before synchronizing removed placements.
    view = doc["card_view"]
    occupied_ids = {s["id"] for s in occupied(doc)}
    if data.card_view and (
        len(set(view["card_order"])) != len(view["card_order"])
        or set(view["card_order"]) - occupied_ids
    ):
        raise DomainError("ALBUM_CARD_ORDER_INVALID", "轮播顺序必须引用当前相册的小卡实例", 422)
    if (
        data.card_view
        and view.get("featured_slot_id")
        and view["featured_slot_id"] not in occupied_ids
    ):
        raise DomainError("ALBUM_FEATURED_INVALID", "关键卡面必须引用已有小卡实例", 422)
    sync_card_view(doc)
    # Preserve the original public edition on the first edit of a legacy book.
    if album.status == "PUBLISHED" and album.published_snapshot is None:
        album.published_snapshot = deepcopy(previous)
    claim(db, album, data.revision)
    for key in ("name", "description", "display_type", "visual_style"):
        setattr(album, key, doc[key].strip() if key == "name" else doc[key])
    album.cover_config, album.card_view_config = doc["cover"], doc["card_view"]
    if data.card_instances is not None:
        db.get(AlbumWork, album.id).instances = doc["card_instances"]
    if data.visibility is not None:
        album.is_public = data.visibility == "PUBLIC"
    if data.pages is not None:
        persist_pages(db, album, doc["pages"])
    db.flush()
    return album


def validate_publication(db: Session, album: CardAlbum, doc: dict) -> None:
    text = " ".join(
        [
            doc["name"],
            doc["description"],
            *[
                e["content"]
                for canvas in [doc["cover"], *[p["config"] for p in doc["pages"]]]
                for e in canvas.get("elements", [])
                if e["type"] == "TEXT"
            ],
        ]
    )
    if any(term and term.lower() in text.lower() for term in limits(db)["blocked_terms"]):
        raise DomainError("ALBUM_CONTENT_REVIEW_REQUIRED", "公开内容需修改后再发布", 422)
    if album.is_moderated:
        raise DomainError("ALBUM_MODERATED", "相册已限制公开展示，请联系运营复核", 403)


def publish(db: Session, album: CardAlbum, revision: int) -> None:
    lock_quota(db, db.get(User, album.user_id))
    db.refresh(album)
    if album.is_moderated:
        raise DomainError("ALBUM_MODERATED", "作品仍受公开限制，请先申请运营复核", 403)
    doc = document(db, album)
    if album.is_public:
        validate_publication(db, album, doc)
    sync_card_view(doc)
    claim(db, album, revision)
    album.published_snapshot = doc
    album.status = "PUBLISHED"
    album.published_at = utcnow()
    album.publication_blocked = False
    db.flush()


def duplicate_document(doc: dict) -> dict:
    copy = deepcopy(doc)
    mapping = {}
    for instance in copy.get("card_instances", []):
        mapping[instance["id"]] = new_id("instance")
        instance["id"] = mapping[instance["id"]]
    for page in copy["pages"]:
        page["id"] = new_id("page")
        for slot in page["slots"]:
            mapping[slot["id"]] = new_id("slot")
            slot["id"] = mapping[slot["id"]]
        for e in page["config"].get("elements", []):
            e["id"] = new_id("element")
    for e in copy["cover"].get("elements", []):
        e["id"] = new_id("element")
    view = copy["card_view"]
    view["card_order"] = [mapping[s] for s in view.get("card_order", []) if s in mapping]
    view["featured_slot_id"] = mapping.get(view.get("featured_slot_id"))
    return copy
