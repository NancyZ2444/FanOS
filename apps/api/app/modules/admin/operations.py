from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.admin_models import ContentMetadata
from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_admin
from app.future_models import NotificationInboxItem
from app.models import (
    Card,
    CatalogAlbum,
    Comment,
    DailyCardDraw,
    Group,
    Idol,
    IdolOfficialAccount,
    Report,
    SocialPost,
    User,
    UserCollectionItem,
    UserIdol,
    UserSocialAccount,
    UserWishlistItem,
    new_id,
)
from app.modules.admin.catalog_service import (
    audit,
    meta_for,
    permit,
    row_data,
)
from app.modules.admin.console_schemas import ActionRequest, OpsDraft

router = APIRouter(prefix="/admin/console", tags=["Admin Operations"])
MANAGED = {"notifications", "announcements", "daily"}


def audience(db: Session, data: dict) -> list[str]:
    query = select(User.id).where(User.is_active.is_(True), User.role == "user")
    if data.get("audience") == "FAVORITE_IDOL":
        query = query.where(
            User.id.in_(
                select(UserIdol.user_id).where(UserIdol.idol_id == data.get("audience_idol_id"))
            )
        )
    return list(db.scalars(query).all())


def managed_payload(db: Session, row: ContentMetadata) -> dict:
    result = {
        **row.data,
        "id": row.entity_id,
        "status": row.status,
        "created_at": row.created_at.isoformat(),
        "operator": row.operator_id,
    }
    if row.entity_type == "notifications":
        result["audience_count"] = len(audience(db, row.data))
    return result


def validate_target(db: Session, data: dict) -> None:
    kind = data.get("target_type", "NONE")
    if kind == "NONE":
        return
    model = {"CARD": Card, "ALBUM": CatalogAlbum, "GROUP": Group, "IDOL": Idol}.get(kind)
    target = db.get(model, data.get("target_id")) if model and data.get("target_id") else None
    if not target:
        raise DomainError("INVALID_TARGET", "跳转目标不存在", 422)
    meta_kind = {"ALBUM": "albums", "GROUP": "groups", "IDOL": "idols"}.get(kind)
    meta = meta_for(db, meta_kind, target.id) if meta_kind else None
    if (
        (kind == "CARD" and target.status != "PUBLISHED")
        or (kind == "ALBUM" and not target.is_published)
        or (meta and meta.status != "PUBLISHED")
    ):
        raise DomainError("INVALID_TARGET", "目标内容当前不可访问，请重新选择", 422)


def user_payload(db: Session, user: User) -> dict:
    return {
        "id": user.id,
        "title": user.display_name,
        "name": user.display_name,
        "avatar_url": user.avatar_url,
        "bio": user.bio,
        "role": user.role,
        "status": "NORMAL" if user.is_active else "BANNED",
        "phone": (user.phone[:3] + "****" + user.phone[-4:]) if user.phone else "",
        "created_at": user.created_at.isoformat(),
        "level": user.level,
        "collection_count": db.scalar(
            select(func.count())
            .select_from(UserCollectionItem)
            .where(UserCollectionItem.user_id == user.id)
        )
        or 0,
        "wishlist_count": db.scalar(
            select(func.count())
            .select_from(UserWishlistItem)
            .where(UserWishlistItem.user_id == user.id)
        )
        or 0,
        "favorite_ids": list(
            db.scalars(select(UserIdol.idol_id).where(UserIdol.user_id == user.id))
        ),
        "accounts": [
            {
                "platform": a.platform,
                "display_name": a.display_name,
                "platform_user_id": "****" + a.platform_user_id[-4:],
                "created_at": a.created_at.isoformat(),
            }
            for a in db.scalars(
                select(UserSocialAccount).where(UserSocialAccount.user_id == user.id)
            )
        ],
    }


@router.get("/dashboard")
def dashboard(actor: User = Depends(current_admin), db: Session = Depends(get_db)) -> dict:
    cards = db.scalars(select(Card)).all()
    today = datetime.now(UTC).date()

    def count(model):
        return db.scalar(select(func.count()).select_from(model)) or 0

    return success(
        {
            "users": count(User),
            "groups": count(Group),
            "idols": count(Idol),
            "cards": sum(c.status != "ARCHIVED" for c in cards),
            "published": sum(c.status == "PUBLISHED" for c in cards),
            "pending": sum(c.status == "PENDING" for c in cards),
            "drafts": sum(c.status == "DRAFT" for c in cards),
            "missing_images": sum(not c.image_url for c in cards if c.status != "ARCHIVED"),
            "source_issues": sum(
                not c.admin_data.get("front_source", {}).get("source_url")
                or c.admin_data.get("front_source", {}).get("copyright_status", "UNKNOWN")
                == "UNKNOWN"
                for c in cards
                if c.status != "ARCHIVED"
            ),
            "today_cards": sum(c.created_at.date() == today for c in cards),
            "social_posts": count(SocialPost),
            "draws": count(DailyCardDraw),
            "reports": db.scalar(
                select(func.count()).select_from(Report).where(Report.status == "pending")
            )
            or 0,
        }
    )


@router.get("/operations/{kind}")
def list_operations(
    kind: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
) -> dict:
    domain = "social" if kind == "accounts" else "daily" if kind == "draws" else kind
    permit(actor, domain)
    if kind in MANAGED:
        items = [
            managed_payload(db, row)
            for row in db.scalars(
                select(ContentMetadata)
                .where(ContentMetadata.entity_type == kind)
                .order_by(ContentMetadata.updated_at.desc())
            )
        ]
    elif kind == "users":
        items = [
            user_payload(db, row)
            for row in db.scalars(select(User).order_by(User.created_at.desc()))
        ]
    elif kind == "social":
        items = [
            {
                **row_data(row),
                "title": row.content,
                "status": "PUBLISHED" if row.is_available else "OFFLINE",
                "card_ids": (row.relation or {}).get("card_ids", []),
            }
            for row in db.scalars(select(SocialPost).order_by(SocialPost.posted_at.desc()))
        ]
    elif kind == "accounts":
        items = [
            {
                **row_data(row),
                "title": row.handle,
                "status": "NORMAL" if row.is_active else "OFFLINE",
            }
            for row in db.scalars(select(IdolOfficialAccount))
        ]
    elif kind == "comments":
        items = []
        for row in db.scalars(select(Comment).order_by(Comment.created_at.desc())):
            meta = meta_for(db, "comments", row.id)
            user = db.get(User, row.user_id)
            post = db.get(SocialPost, row.post_id)
            items.append(
                {
                    **row_data(row),
                    "title": row.content,
                    "status": meta.status if meta else ("DELETED" if row.is_deleted else "VISIBLE"),
                    "user_name": user.display_name if user else "",
                    "post_content": post.content if post else "",
                }
            )
    elif kind == "reports":
        items = [
            {**row_data(row), "title": row.reason, "status": row.status.upper()}
            for row in db.scalars(select(Report).order_by(Report.created_at.desc()))
        ]
    elif kind == "draws":
        items = [
            {**row_data(row), "title": db.get(Card, row.card_id).title, "status": "COMPLETED"}
            for row in db.scalars(select(DailyCardDraw).order_by(DailyCardDraw.created_at.desc()))
        ]
    else:
        raise DomainError("MODULE_NOT_FOUND", "模块不存在", 404)
    return success({"items": items})


@router.post("/operations/{kind}")
def create_operation(
    kind: str,
    payload: OpsDraft,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
) -> dict:
    return save_operation(kind, None, payload, actor, db)


@router.put("/operations/{kind}/{item_id}")
def edit_operation(
    kind: str,
    item_id: str,
    payload: OpsDraft,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
) -> dict:
    return save_operation(kind, item_id, payload, actor, db)


def save_operation(
    kind: str, item_id: str | None, payload: OpsDraft, actor: User, db: Session
) -> dict:
    permit(actor, "social" if kind == "accounts" else kind, "edit")
    data = payload.model_dump()
    if payload.group_id and not db.get(Group, payload.group_id):
        raise DomainError("INVALID_GROUP", "所选组合不存在", 422)
    if payload.idol_id and not db.get(Idol, payload.idol_id):
        raise DomainError("INVALID_IDOL", "所选艺人不存在", 422)
    for card_id in payload.card_ids:
        card = db.get(Card, card_id)
        if not card or card.status != "PUBLISHED":
            raise DomainError("INVALID_CARD", "只能关联已发布的小卡", 422)
    if kind in MANAGED:
        row = meta_for(db, kind, item_id) if item_id else None
        if item_id and not row:
            raise DomainError("NOT_FOUND", "内容不存在", 404)
        if row and row.status not in {"DRAFT", "REJECTED", "OFFLINE"}:
            raise DomainError("NOT_EDITABLE", "当前状态不可修改，请先下架或驳回", 409)
        validate_target(db, data)
        if payload.audience == "FAVORITE_IDOL" and not db.get(Idol, payload.audience_idol_id):
            raise DomainError("INVALID_AUDIENCE", "请选择目标人群的本命艺人", 422)
        if kind == "daily" and (
            not payload.weights or any(v <= 0 for v in payload.weights.values())
        ):
            raise DomainError(
                "INVALID_WEIGHTS", "卡池须至少包含一张小卡，且所有权重必须大于 0", 422
            )
        if kind == "daily":
            for card_id in payload.weights:
                card = db.get(Card, card_id)
                if not card or card.status != "PUBLISHED":
                    raise DomainError("INVALID_CARD", "卡池只能选择已发布小卡", 422)
        for key in ("start_time", "end_time"):
            if data[key]:
                try:
                    value = datetime.fromisoformat(data[key].replace("Z", "+00:00"))
                    if value.tzinfo is None:
                        raise ValueError("timezone required")
                    data[key] = value.astimezone(UTC).isoformat()
                except ValueError as exc:
                    raise DomainError("INVALID_TIME", "时间必须包含时区", 422) from exc
        if data["start_time"] and data["end_time"] and data["end_time"] <= data["start_time"]:
            raise DomainError("INVALID_TIME_RANGE", "结束时间必须晚于开始时间", 422)
        before = managed_payload(db, row) if row else None
        if not row:
            row = ContentMetadata(
                entity_type=kind,
                entity_id=new_id(kind),
                status="DRAFT",
                data={},
                operator_id=actor.id,
            )
            db.add(row)
        row.data = data
        row.operator_id = actor.id
        db.flush()
        result = managed_payload(db, row)
    elif kind == "social":
        if not payload.group_id and not payload.idol_id:
            raise DomainError("BINDING_REQUIRED", "动态至少关联一个组合或艺人", 422)
        row = db.get(SocialPost, item_id) if item_id else None
        if item_id and not row:
            raise DomainError("NOT_FOUND", "动态不存在", 404)
        before = row_data(row) if row else None
        if not row:
            row = SocialPost(
                original_post_id=new_id("manual"),
                posted_at=datetime.now(UTC),
                fetched_at=datetime.now(UTC),
                is_available=False,
            )
            db.add(row)
        row.content = payload.content or payload.title
        row.platform = payload.platform
        row.original_url = payload.source_url
        row.group_id = payload.group_id or None
        row.idol_id = payload.idol_id or None
        row.relation = {"card_ids": payload.card_ids}
        row.media = [{"type": "image", "url": payload.image_url}] if payload.image_url else []
        db.flush()
        result = row_data(row)
    elif kind == "accounts":
        if not payload.idol_id and not payload.group_id:
            raise DomainError("BINDING_REQUIRED", "账号至少关联一个组合或艺人", 422)
        row = db.get(IdolOfficialAccount, item_id) if item_id else None
        before = row_data(row) if row else None
        duplicate = db.scalar(
            select(IdolOfficialAccount).where(
                IdolOfficialAccount.platform == payload.platform,
                IdolOfficialAccount.platform_account_id == payload.title,
            )
        )
        if duplicate and duplicate.id != item_id:
            raise DomainError("DUPLICATE_ACCOUNT", "该平台账号已存在", 409)
        if not row:
            row = IdolOfficialAccount()
            db.add(row)
        row.platform = payload.platform
        row.platform_account_id = payload.title
        row.handle = payload.content or payload.title
        row.group_id = payload.group_id or None
        row.idol_id = payload.idol_id or None
        db.flush()
        result = row_data(row)
    else:
        raise DomainError("MODULE_READ_ONLY", "该模块不支持新建", 422)
    audit(db, actor, f"{kind}.save", kind, result.get("id", ""), before, result)
    db.commit()
    return success(result)


@router.post("/operations/{kind}/{item_id}/actions")
def operation_action(
    kind: str,
    item_id: str,
    payload: ActionRequest,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
) -> dict:
    permit(actor, "social" if kind == "accounts" else kind, payload.action)
    action = payload.action
    if kind in MANAGED:
        row = db.scalar(
            select(ContentMetadata)
            .where(ContentMetadata.entity_type == kind, ContentMetadata.entity_id == item_id)
            .with_for_update()
        )
        if not row:
            raise DomainError("NOT_FOUND", "内容不存在", 404)
        before = managed_payload(db, row)
        transition = {
            "submit": ({"DRAFT", "REJECTED", "OFFLINE"}, "PENDING"),
            "approve": ({"PENDING"}, "APPROVED" if kind == "notifications" else "PUBLISHED"),
            "publish": ({"PENDING"}, "PUBLISHED"),
            "offline": ({"PUBLISHED"}, "OFFLINE"),
            "reject": ({"PENDING"}, "REJECTED"),
            "cancel": ({"DRAFT", "APPROVED"}, "CANCELLED"),
        }
        if action == "test-send" and kind == "notifications":
            if row.status not in {"DRAFT", "PENDING", "APPROVED"}:
                raise DomainError("INVALID_TRANSITION", "当前状态不可测试发送", 409)
            validate_target(db, row.data)
            db.add(
                NotificationInboxItem(
                    user_id=actor.id,
                    category="TEST",
                    source_type="TEST",
                    source_id=item_id,
                    title="[TEST] " + row.data["title"][:150],
                    body=row.data["content"],
                    payload=row.data,
                )
            )
        elif action == "send" and kind == "notifications":
            if row.status != "APPROVED":
                raise DomainError("APPROVAL_REQUIRED", "请先完成审核", 409)
            validate_target(db, row.data)
            ids = audience(db, row.data)
            if len(ids) > 10000 and payload.confirmation != "SEND":
                raise DomainError(
                    "CONFIRM_REQUIRED", "本次发送超过 10000 人，请输入 SEND 确认", 422
                )
            for user_id in ids:
                db.add(
                    NotificationInboxItem(
                        user_id=user_id,
                        category="OPERATION",
                        source_type="notification",
                        source_id=item_id,
                        title=row.data["title"],
                        body=row.data["content"],
                        payload=row.data,
                    )
                )
            row.status = "SENT"
            row.data = {
                **row.data,
                "sent_count": len(ids),
                "sent_at": datetime.now(UTC).isoformat(),
            }
        else:
            allowed, target = transition.get(action, (set(), ""))
            if row.status not in allowed or (kind == "notifications" and action == "publish"):
                raise DomainError("INVALID_TRANSITION", "当前状态不允许此操作", 409)
            if action in {"approve", "publish", "submit"}:
                validate_target(db, row.data)
            if action == "reject" and not payload.reason.strip():
                raise DomainError("REASON_REQUIRED", "请填写驳回原因", 422)
            if kind == "daily" and target == "PUBLISHED":
                for other in db.scalars(
                    select(ContentMetadata).where(
                        ContentMetadata.entity_type == "daily",
                        ContentMetadata.status == "PUBLISHED",
                    )
                ):
                    if other.id != row.id:
                        raise DomainError(
                            "POOL_CONFLICT", "请先下架当前启用的卡池，避免规则冲突", 409
                        )
            row.status = target
        row.data = {**row.data, "review_note": payload.reason}
        result = managed_payload(db, row)
    else:
        model = {
            "social": SocialPost,
            "accounts": IdolOfficialAccount,
            "comments": Comment,
            "reports": Report,
            "users": User,
        }.get(kind)
        row = db.get(model, item_id) if model else None
        if not row:
            raise DomainError("NOT_FOUND", "内容不存在", 404)
        before = user_payload(db, row) if kind == "users" else row_data(row)
        if kind in {"comments", "reports", "users"} and not payload.reason.strip():
            raise DomainError("REASON_REQUIRED", "请填写处理原因", 422)
        if kind == "users" and action in {"ban", "unban"}:
            if row.role != "user":
                raise DomainError("PROTECTED_ACCOUNT", "此入口不允许封禁管理员账号", 422)
            row.is_active = action == "unban"
        elif kind == "comments" and action in {"hide", "delete", "restore"}:
            row.is_deleted = action != "restore"
            meta = meta_for(db, kind, item_id)
            if not meta:
                meta = ContentMetadata(entity_type=kind, entity_id=item_id, operator_id=actor.id)
                db.add(meta)
            meta.status = {"hide": "HIDDEN", "delete": "DELETED", "restore": "VISIBLE"}[action]
            meta.data = {"reason": payload.reason}
        elif kind == "reports" and action in {"resolve", "reject"}:
            if row.status not in {"pending", "under_review"}:
                raise DomainError("INVALID_TRANSITION", "举报已处理", 409)
            row.status = "resolved" if action == "resolve" else "rejected"
        elif kind == "social" and action in {"publish", "offline"}:
            row.is_available = action == "publish"
        elif kind == "accounts" and action in {"publish", "offline"}:
            row.is_active = action == "publish"
        else:
            raise DomainError("INVALID_ACTION", "不支持此操作", 422)
        result = user_payload(db, row) if kind == "users" else row_data(row)
        result["review_note"] = payload.reason
    audit(db, actor, f"{kind}.{action}", kind, item_id, before, result)
    db.commit()
    return success(result)
