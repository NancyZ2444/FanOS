from __future__ import annotations

from copy import deepcopy
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.album_models import (
    AlbumEntitlement,
    AlbumPreferences,
    AlbumReaction,
    AlbumResource,
    AlbumSettings,
)
from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_admin, current_user, optional_user
from app.models import Card, CardAlbum, Report, User, new_id
from app.modules.admin.catalog_service import audit, permit
from app.modules.albums import service
from app.modules.albums.schemas import (
    AlbumCreate,
    AlbumLimits,
    AlbumPatch,
    AlbumReport,
    CardAssetsRequest,
    CardViewPatch,
    CoverPatch,
    DisplayPatch,
    EntitlementPatch,
    ModerationPatch,
    OrderPatch,
    PageCreate,
    PagePatch,
    PreferencesPatch,
    ResourcePatch,
    Revision,
    SlotsPatch,
    VisibilityPatch,
)

router = APIRouter(tags=["Digital Albums"])


def saved(db: Session, album: CardAlbum, user: User) -> dict:
    db.commit()
    db.refresh(album)
    return success(service.payload(db, album, user))


@router.get("/albums/quota")
def quota(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return success(service.quota(db, user))


@router.get("/albums/resources")
def resources(db: Session = Depends(get_db)):
    return success({"items": service.resources(db)})


@router.post("/albums/card-assets")
def card_assets(
    data: CardAssetsRequest, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    from app.common.serializers import card_payload

    result = {}
    for card_id in set(data.card_ids):
        card = db.get(Card, card_id)
        if not service.card_available(card):
            result[card_id] = {"id": card_id, "available": False, "title": "小卡暂不可用"}
            continue
        result[card_id] = {**card_payload(db, card), "available": True}
        if (card.admin_data or {}).get("back_source", {}).get("copyright_status") in {
            "REVOKED",
            "UNAUTHORIZED",
            "EXPIRED",
            "FORBIDDEN",
            "OFFLINE",
            "REJECTED",
        }:
            result[card_id]["back_image_url"] = None
    return success({"cards": result})


@router.get("/albums/preferences")
def preferences(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return success(service.preferences(db, user))


@router.put("/albums/preferences")
def set_preferences(
    data: PreferencesPatch, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    available = {r["id"] for r in service.resources(db) if r["kind"] == "SHELF"}
    if data.shelf_theme not in available:
        raise DomainError("ALBUM_THEME_UNAVAILABLE", "书架主题暂不可用", 422)
    row = db.get(AlbumPreferences, user.id)
    if not row:
        row = AlbumPreferences(user_id=user.id)
        db.add(row)
    row.shelf_theme, row.view_mode = data.shelf_theme, data.view_mode
    db.commit()
    return success(service.preferences(db, user))


@router.get("/albums")
def albums(
    q: str = Query(default="", max_length=50),
    sort: str = "updated",
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=50),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    query = select(CardAlbum).where(CardAlbum.user_id == user.id, CardAlbum.status != "DELETED")
    if q:
        query = query.where(CardAlbum.name.ilike(f"%{q}%"))
    order = {
        "updated": CardAlbum.updated_at.desc(),
        "created": CardAlbum.created_at.desc(),
        "name": CardAlbum.name,
        "custom": CardAlbum.sort_order,
    }.get(sort)
    if order is None:
        raise DomainError("ALBUM_INVALID_SORT", "不支持的相册排序", 422)
    rows = db.scalars(query.order_by(order, CardAlbum.id).offset(offset).limit(limit + 1)).all()
    return success(
        {
            "items": [service.payload(db, r, user, summary=True) for r in rows[:limit]],
            "next_offset": offset + limit if len(rows) > limit else None,
            "quota": service.quota(db, user),
            "preferences": service.preferences(db, user),
        }
    )


@router.post("/albums")
def create(data: AlbumCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return saved(db, service.create(db, user, data), user)


@router.get("/users/me/favorite-albums")
def favorites(
    q: str = Query(default="", max_length=50),
    sort: str = "updated",
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=50),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    title = func.coalesce(CardAlbum.published_snapshot["name"].as_string(), CardAlbum.name)
    query = (
        select(AlbumReaction)
        .join(CardAlbum, CardAlbum.id == AlbumReaction.album_id)
        .where(AlbumReaction.user_id == user.id, AlbumReaction.kind == "FAVORITE")
    )
    if q:
        query = query.where(
            title.ilike(f"%{q}%"),
            CardAlbum.is_public.is_(True),
            CardAlbum.is_moderated.is_(False),
            CardAlbum.status == "PUBLISHED",
        )
    order = {
        "updated": CardAlbum.updated_at.desc(),
        "created": AlbumReaction.created_at.desc(),
        "name": title,
    }.get(sort)
    if order is None:
        raise DomainError("ALBUM_INVALID_SORT", "不支持的相册排序", 422)
    rows = db.scalars(query.order_by(order, AlbumReaction.id).offset(offset).limit(limit + 1)).all()
    result = []
    for reaction in rows[:limit]:
        try:
            album = service.get_album(db, reaction.album_id, user)
            result.append(service.payload(db, album, user, summary=True))
        except DomainError:
            result.append(
                {
                    "id": reaction.album_id,
                    "name": "相册暂不可访问",
                    "unavailable": True,
                    "favorited": True,
                    "card_count": 0,
                    "page_count": 0,
                }
            )
    return success({"items": result, "next_offset": offset + limit if len(rows) > limit else None})


@router.get("/users/{user_id}/albums")
def public_albums(
    user_id: str,
    q: str = Query(default="", max_length=50),
    sort: str = "updated",
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=50),
    viewer: User | None = Depends(optional_user),
    db: Session = Depends(get_db),
):
    owner = db.get(User, user_id)
    if not owner or not owner.is_active:
        raise DomainError("USER_NOT_FOUND", "用户不存在", 404)
    if not owner.albums_visible and (not viewer or viewer.id != owner.id):
        return success({"items": [], "next_offset": None})
    query = select(CardAlbum).where(CardAlbum.user_id == user_id, CardAlbum.status != "DELETED")
    if not viewer or viewer.id != user_id:
        query = query.where(
            CardAlbum.is_public.is_(True),
            CardAlbum.status == "PUBLISHED",
            CardAlbum.is_moderated.is_(False),
        )
    title = func.coalesce(CardAlbum.published_snapshot["name"].as_string(), CardAlbum.name)
    if q:
        query = query.where(
            (CardAlbum.name if viewer and viewer.id == owner.id else title).ilike(f"%{q}%")
        )
    order = {
        "updated": CardAlbum.updated_at.desc(),
        "created": CardAlbum.created_at.desc(),
        "name": title,
    }.get(sort)
    if order is None:
        raise DomainError("ALBUM_INVALID_SORT", "不支持的相册排序", 422)
    rows = db.scalars(query.order_by(order, CardAlbum.id).offset(offset).limit(limit + 1)).all()
    return success(
        {
            "items": [service.payload(db, r, viewer, summary=True) for r in rows[:limit]],
            "next_offset": offset + limit if len(rows) > limit else None,
        }
    )


@router.get("/albums/{album_id}")
@router.get("/albums/{album_id}/preview")
def detail(
    album_id: str,
    published: bool = False,
    viewer: User | None = Depends(optional_user),
    db: Session = Depends(get_db),
):
    return success(
        service.payload(db, service.get_album(db, album_id, viewer), viewer, published=published)
    )


@router.patch("/albums/{album_id}")
def patch(
    album_id: str,
    data: AlbumPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    album = service.get_album(db, album_id, user, edit=True)
    return saved(db, service.patch(db, album, user, data), user)


@router.delete("/albums/{album_id}")
def remove(
    album_id: str,
    revision: int = Query(ge=1),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    album = service.get_album(db, album_id, user, edit=True)
    service.claim(db, album, revision)
    album.status = "DELETED"
    album.is_public = False
    db.commit()
    return success({"id": album.id, "status": "DELETED", "revision": album.revision})


@router.post("/albums/{album_id}/publish")
def publish(
    album_id: str, data: Revision, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    album = service.get_album(db, album_id, user, edit=True)
    service.publish(db, album, data.revision)
    return saved(db, album, user)


@router.post("/albums/{album_id}/duplicate")
def duplicate(
    album_id: str, data: Revision, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    source = service.get_album(db, album_id, user, edit=True)
    if source.revision != data.revision:
        raise DomainError("ALBUM_REVISION_CONFLICT", "相册已更新，请重新加载", 409)
    doc = service.duplicate_document(service.document(db, source))
    if len(doc["pages"]) > service.quota(db, user)["max_page_per_album"]:
        raise DomainError("ALBUM_PAGE_QUOTA_EXCEEDED", "复制相册超过当前页面额度", 409)
    target = service.create(
        db,
        user,
        AlbumCreate(
            name=(source.name[:45] + " 副本"),
            description=source.description,
            display_type=source.display_type,
            visual_style=source.visual_style,
        ),
    )
    target.cover_config, target.card_view_config = doc["cover"], doc["card_view"]
    service.persist_pages(db, target, doc["pages"])
    return saved(db, target, user)


def edit_page(db: Session, album_id: str, page_id: str, user: User):
    album = service.get_album(db, album_id, user, edit=True)
    doc = service.document(db, album)
    page = next((p for p in doc["pages"] if p["id"] == page_id), None)
    if not page:
        raise DomainError("ALBUM_PAGE_NOT_FOUND", "相册页面不存在", 404)
    return album, doc, page


@router.get("/albums/{album_id}/pages")
def pages(
    album_id: str, viewer: User | None = Depends(optional_user), db: Session = Depends(get_db)
):
    result = service.payload(db, service.get_album(db, album_id, viewer), viewer)
    return success(
        {"items": result["pages"], "cards": result["cards"], "revision": result["revision"]}
    )


@router.post("/albums/{album_id}/pages")
def add_page(
    album_id: str,
    data: PageCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    album = service.get_album(db, album_id, user, edit=True)
    doc = service.document(db, album)
    at = len(doc["pages"])
    if data.after_page_id:
        indices = [i for i, p in enumerate(doc["pages"]) if p["id"] == data.after_page_id]
        if not indices:
            raise DomainError("ALBUM_PAGE_NOT_FOUND", "相册页面不存在", 404)
        at = indices[0] + 1
    doc["pages"].insert(
        at,
        {
            "id": new_id("page"),
            "grid_count": data.grid_count,
            "slots": [{"id": new_id("slot"), "card_id": None} for _ in range(data.grid_count)],
        },
    )
    return saved(
        db,
        service.patch(db, album, user, AlbumPatch(revision=data.revision, pages=doc["pages"])),
        user,
    )


@router.put("/albums/{album_id}/pages/reorder")
def reorder(
    album_id: str,
    data: OrderPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    album = service.get_album(db, album_id, user, edit=True)
    doc = service.document(db, album)
    mapping = {p["id"]: p for p in doc["pages"]}
    if len(data.page_ids) != len(mapping) or set(data.page_ids) != set(mapping):
        raise DomainError("ALBUM_INVALID_PAGE_ORDER", "排序需要包含每个页面且不能重复", 422)
    return saved(
        db,
        service.patch(
            db,
            album,
            user,
            AlbumPatch(revision=data.revision, pages=[mapping[p] for p in data.page_ids]),
        ),
        user,
    )


@router.patch("/albums/{album_id}/pages/{page_id}")
def patch_page(
    album_id: str,
    page_id: str,
    data: PagePatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    album, doc, page = edit_page(db, album_id, page_id, user)
    if data.grid_count:
        filled = [s for s in page["slots"] if s["card_id"]]
        empty = [s for s in page["slots"] if not s["card_id"]]
        slots = filled + empty
        page["slots"] = slots[: data.grid_count] + [
            {"id": new_id("slot"), "card_id": None}
            for _ in range(max(0, data.grid_count - len(slots)))
        ]
        page["grid_count"] = data.grid_count
    if data.config:
        page["config"] = data.config.model_dump()
    return saved(
        db,
        service.patch(
            db,
            album,
            user,
            AlbumPatch(
                revision=data.revision, pages=doc["pages"], confirm_removal=data.confirm_removal
            ),
        ),
        user,
    )


@router.delete("/albums/{album_id}/pages/{page_id}")
def remove_page(
    album_id: str,
    page_id: str,
    revision: int = Query(ge=1),
    confirm_removal: bool = False,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    album, doc, page = edit_page(db, album_id, page_id, user)
    doc["pages"].remove(page)
    return saved(
        db,
        service.patch(
            db,
            album,
            user,
            AlbumPatch(revision=revision, pages=doc["pages"], confirm_removal=confirm_removal),
        ),
        user,
    )


@router.post("/albums/{album_id}/pages/{page_id}/duplicate")
def copy_page(
    album_id: str,
    page_id: str,
    data: Revision,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    album, doc, page = edit_page(db, album_id, page_id, user)
    clone = deepcopy(page)
    clone["id"] = new_id("page")
    for slot in clone["slots"]:
        slot["id"] = new_id("slot")
    for e in clone["config"].get("elements", []):
        e["id"] = new_id("element")
    doc["pages"].insert(doc["pages"].index(page) + 1, clone)
    return saved(
        db,
        service.patch(
            db,
            album,
            user,
            AlbumPatch(revision=data.revision, pages=doc["pages"], confirm_duplicates=True),
        ),
        user,
    )


@router.put("/albums/{album_id}/pages/{page_id}/slots")
def slots(
    album_id: str,
    page_id: str,
    data: SlotsPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    album, doc, page = edit_page(db, album_id, page_id, user)
    if {s.id for s in data.slots} != {s["id"] for s in page["slots"]}:
        raise DomainError("ALBUM_INVALID_IDS", "更新卡位须保留当前页的全部卡位 ID", 422)
    page["slots"] = [s.model_dump() for s in data.slots]
    return saved(
        db,
        service.patch(
            db,
            album,
            user,
            AlbumPatch(
                revision=data.revision,
                pages=doc["pages"],
                confirm_duplicates=data.confirm_duplicates,
            ),
        ),
        user,
    )


@router.put("/albums/{album_id}/cover")
def cover(
    album_id: str,
    data: CoverPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    return patch(album_id, AlbumPatch(revision=data.revision, cover=data.cover), user, db)


@router.put("/albums/{album_id}/display")
def display(
    album_id: str,
    data: DisplayPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    return patch(album_id, AlbumPatch(**data.model_dump()), user, db)


@router.put("/albums/{album_id}/card-view")
def card_view(
    album_id: str,
    data: CardViewPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    return patch(album_id, AlbumPatch(**data.model_dump()), user, db)


@router.put("/albums/{album_id}/visibility")
def visibility(
    album_id: str,
    data: VisibilityPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    return patch(album_id, AlbumPatch(**data.model_dump()), user, db)


def react(db: Session, album_id: str, user: User, kind: str, active: bool):
    # Check visibility after the write lock, not before a concurrent private/delete.
    service.lock_quota(db, user)
    db.expire_all()
    if active:
        album = service.get_album(db, album_id, user)
        if album.user_id == user.id:
            raise DomainError("ALBUM_SELF_REACTION", "自己的作品无需点赞或收藏", 422)
    # Serialize inserts and keep them idempotent, including concurrent double taps.
    existing = db.scalar(
        select(AlbumReaction).where(
            AlbumReaction.album_id == album_id,
            AlbumReaction.user_id == user.id,
            AlbumReaction.kind == kind,
        )
    )
    if active and not existing:
        db.add(AlbumReaction(album_id=album_id, user_id=user.id, kind=kind))
    elif not active and existing:
        db.delete(existing)
    db.commit()
    return success({"active": active})


@router.post("/albums/{album_id}/like")
def like(album_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return react(db, album_id, user, "LIKE", True)


@router.delete("/albums/{album_id}/like")
def unlike(album_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return react(db, album_id, user, "LIKE", False)


@router.post("/albums/{album_id}/favorite")
def favorite(album_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return react(db, album_id, user, "FAVORITE", True)


@router.delete("/albums/{album_id}/favorite")
def unfavorite(album_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return react(db, album_id, user, "FAVORITE", False)


@router.post("/albums/{album_id}/report")
def report(
    album_id: str,
    data: AlbumReport,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    service.get_album(db, album_id, user)
    db.add(
        Report(
            reporter_id=user.id, target_type="digital_album", target_id=album_id, reason=data.reason
        )
    )
    db.commit()
    return success({"submitted": True})


@router.get("/admin/console/digital-albums")
def admin_albums(
    q: str = "",
    user_id: str = "",
    status: str = "",
    created_from: str = "",
    created_to: str = "",
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "reports")
    query = select(CardAlbum)
    if q:
        query = query.where(CardAlbum.name.ilike(f"%{q}%"))
    if user_id:
        query = query.where(CardAlbum.user_id == user_id)
    if status:
        query = query.where(CardAlbum.status == status)
    for value, lower in [(created_from, True), (created_to, False)]:
        if value:
            try:
                date = datetime.fromisoformat(value)
            except ValueError as exc:
                raise DomainError("INVALID_DATE", "日期格式不正确", 422) from exc
            query = query.where(
                CardAlbum.created_at >= date if lower else CardAlbum.created_at <= date
            )
    items = []
    for row in db.scalars(query.order_by(CardAlbum.updated_at.desc()).limit(200)):
        item = service.payload(db, row, db.get(User, row.user_id), summary=False)
        item["report_count"] = len(
            db.scalars(
                select(Report).where(
                    Report.target_type == "digital_album", Report.target_id == row.id
                )
            ).all()
        )
        items.append(item)
    return success({"items": items})


@router.put("/admin/console/digital-albums/{album_id}/moderation")
def moderate(
    album_id: str,
    data: ModerationPatch,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "reports", "offline")
    row = db.get(CardAlbum, album_id)
    if not row:
        raise DomainError("ALBUM_NOT_FOUND", "相册不存在", 404)
    before = {"is_moderated": row.is_moderated}
    row.is_moderated = data.offline
    audit(db, actor, "moderate", "digital_albums", row.id, before, data.model_dump())
    db.commit()
    return success({"is_moderated": row.is_moderated})


@router.get("/admin/console/album-settings")
def admin_settings(actor: User = Depends(current_admin), db: Session = Depends(get_db)):
    permit(actor, "reports")
    return success(
        {"limits": service.limits(db), "resources": service.resources(db, include_offline=True)}
    )


@router.put("/admin/console/album-settings")
def save_settings(
    data: AlbumLimits, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    if actor.role != "admin":
        raise DomainError("PERMISSION_DENIED", "仅系统管理员可以修改相册额度", 403)
    row = db.get(AlbumSettings, "global")
    before = service.limits(db)
    if not row:
        row = AlbumSettings(id="global")
        db.add(row)
    row.config = data.model_dump()
    audit(db, actor, "configure", "album_settings", "global", before, row.config)
    db.commit()
    return success(service.limits(db))


@router.put("/admin/console/album-resources/{resource_id}")
def save_resource(
    resource_id: str,
    data: ResourcePatch,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    if actor.role != "admin":
        raise DomainError("PERMISSION_DENIED", "仅系统管理员可以管理相册资源", 403)
    if resource_id != data.id:
        raise DomainError("INVALID_RESOURCE_ID", "资源 ID 不一致", 422)
    row = db.get(AlbumResource, resource_id)
    before = service.resource_payload(row) if row else None
    if not row:
        row = AlbumResource(id=resource_id)
        db.add(row)
    for key, value in data.model_dump().items():
        setattr(row, key, value)
    db.flush()
    audit(db, actor, "configure", "album_resources", row.id, before, service.resource_payload(row))
    db.commit()
    return success(service.resource_payload(row))


@router.put("/admin/console/album-entitlements/{user_id}")
def entitlement(
    user_id: str,
    data: EntitlementPatch,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    if actor.role != "admin":
        raise DomainError("PERMISSION_DENIED", "仅系统管理员可以管理会员权益", 403)
    user = db.get(User, user_id)
    if not user:
        raise DomainError("USER_NOT_FOUND", "用户不存在", 404)
    try:
        expiry = (
            datetime.fromisoformat(data.expires_at.replace("Z", "+00:00"))
            if data.expires_at
            else None
        )
    except ValueError as exc:
        raise DomainError("INVALID_DATE", "会员到期时间格式不正确", 422) from exc
    if expiry and expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=UTC)
    row = db.get(AlbumEntitlement, user_id)
    before = {"plan": row.plan, "expires_at": str(row.expires_at)} if row else None
    if not row:
        row = AlbumEntitlement(user_id=user_id)
        db.add(row)
    row.plan, row.expires_at = data.plan, expiry
    audit(db, actor, "entitlement", "album_entitlements", user_id, before, data.model_dump())
    db.commit()
    return success(service.quota(db, user))
