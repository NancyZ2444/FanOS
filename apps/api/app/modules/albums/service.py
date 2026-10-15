from __future__ import annotations

from collections import Counter
from copy import deepcopy
from datetime import UTC

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session, attributes

from app.album_models import (
    AlbumEntitlement,
    AlbumPage,
    AlbumPreferences,
    AlbumReaction,
    AlbumResource,
    AlbumSettings,
    AlbumSlot,
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


def resources(db: Session, *, include_offline=False) -> list[dict]:
    custom = {r.id: r for r in db.scalars(select(AlbumResource)).all()}
    result = []
    for default in DEFAULT_RESOURCES:
        row = custom.pop(default["id"], None)
        result.append(
            resource_payload(row)
            if row
            else {**default, "status": "PUBLISHED", "sort_order": len(result)}
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
        "normal_albums": config["normal_albums"],
        "pro_albums": config["pro_albums"],
        "normal_pages": config["normal_pages"],
        "pro_pages": config["pro_pages"],
    }


def preferences(db: Session, user: User) -> dict:
    row = db.get(AlbumPreferences, user.id)
    return {
        "shelf_theme": row.shelf_theme if row else "cream-white",
        "view_mode": row.view_mode if row else "SHELF",
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
    if not is_owner and (not row.is_public or row.status != "PUBLISHED" or row.is_moderated):
        raise DomainError("ALBUM_UNAVAILABLE", "相册为私密、未发布或暂不可访问", 403)
    return row


def document(db: Session, album: CardAlbum) -> dict:
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
    return {
        "album_id": album.id,
        "name": album.name,
        "description": album.description,
        "display_type": album.display_type,
        "visual_style": album.visual_style,
        "cover": deepcopy(album.cover_config) or CanvasConfig().model_dump(),
        "card_view": deepcopy(album.card_view_config),
        "pages": pages,
    }


def occupied(doc: dict) -> list[dict]:
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
        view["featured_slot_id"] = None
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
    db: Session, album: CardAlbum, viewer: User | None, *, summary=False, published=False
) -> dict:
    from app.common.serializers import card_payload

    owner = viewer is not None and viewer.id == album.user_id
    doc = (
        deepcopy(album.published_snapshot)
        if (published or not owner) and album.published_snapshot
        else document(db, album)
    )
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
    result = {
        "id": album.id,
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
        result.update(pages=doc["pages"], card_view=doc["card_view"])
    return result


def create(db: Session, user: User, data: AlbumCreate) -> CardAlbum:
    lock_quota(db, user)
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
        display_type=data.display_type,
        visual_style=data.visual_style,
        is_public=False,
        status="DRAFT",
        cover_config=CanvasConfig().model_dump(),
        card_view_config={},
    )
    db.add(album)
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
    slots = [s for p in doc["pages"] for s in p["slots"]]
    if len(set(page_ids)) != len(page_ids) or len({s["id"] for s in slots}) != len(slots):
        raise DomainError("ALBUM_INVALID_IDS", "页面和卡位 ID 必须唯一", 422)
    old_pages = {p["id"]: p for p in previous["pages"]}
    old_slots = {s["id"]: s for p in previous["pages"] for s in p["slots"]}
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
    available_stickers = {r["id"] for r in resources(db) if r["kind"] == "STICKER"}
    old_stickers = {
        e["content"]
        for canvas in [previous["cover"], *[p["config"] for p in previous["pages"]]]
        for e in canvas.get("elements", [])
        if e["type"] == "STICKER"
    }
    for canvas in [doc["cover"], *[p["config"] for p in doc["pages"]]]:
        for element in canvas.get("elements", []):
            if (
                element["type"] == "STICKER"
                and element["content"] not in available_stickers | old_stickers
            ):
                raise DomainError("ALBUM_STICKER_UNAVAILABLE", "该官方贴纸暂不可用", 422)
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
    if album.revision != data.revision:
        raise DomainError("ALBUM_REVISION_CONFLICT", "相册已更新，请重新加载；本地草稿会保留", 409)
    if data.pages is not None:
        lock_quota(db, user)
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
    ):
        value = getattr(data, key)
        if value is not None:
            doc[key] = (
                value.model_dump()
                if hasattr(value, "model_dump")
                else [p.model_dump() for p in value]
                if key == "pages"
                else value
            )
    validate_document(db, user, previous, doc, data)
    if data.visibility == "PUBLIC" and album.status == "PUBLISHED":
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
    doc = document(db, album)
    if album.is_public:
        validate_publication(db, album, doc)
    sync_card_view(doc)
    claim(db, album, revision)
    album.published_snapshot = doc
    album.status = "PUBLISHED"
    album.published_at = album.published_at or utcnow()
    db.flush()


def duplicate_document(doc: dict) -> dict:
    copy = deepcopy(doc)
    mapping = {}
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
