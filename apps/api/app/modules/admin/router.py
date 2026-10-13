from __future__ import annotations

from fastapi import APIRouter, Depends, Header
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.response import DomainError, success
from app.common.serializers import card_payload
from app.core.config import get_settings
from app.core.database import get_db
from app.core.security import current_admin
from app.models import Card, OperationLog, Report, ScanFeedback, SocialPost, User
from app.modules.admin.schemas import CardUpsert, FeedbackStatusPatch, UserStatusPatch
from app.modules.social_feed.schemas import WorkerPostBatch

router = APIRouter(prefix="/admin", tags=["Admin"])


def _audit(
    db: Session,
    actor_id: str,
    action: str,
    target_type: str,
    target_id: str,
    before: dict | None,
    after: dict | None,
) -> None:
    db.add(
        OperationLog(
            actor_id=actor_id,
            action=action,
            target_type=target_type,
            target_id=target_id,
            before=before,
            after=after,
        )
    )


def verify_worker(x_worker_token: str | None = Header(default=None)) -> str:
    if x_worker_token != get_settings().worker_token:
        raise DomainError("WORKER_AUTH_REQUIRED", "Worker 凭据无效", 401)
    return "crawler-worker"


@router.get("/cards")
def list_cards(admin: User = Depends(current_admin), db: Session = Depends(get_db)) -> dict:
    cards = db.scalars(select(Card).order_by(Card.updated_at.desc())).all()
    return success({"items": [card_payload(db, card) for card in cards]})


@router.post("/cards")
def upsert_card(
    payload: CardUpsert, admin: User = Depends(current_admin), db: Session = Depends(get_db)
) -> dict:
    from app.modules.admin.catalog_service import admin_card, save_card
    from app.modules.admin.console_schemas import CardDraft

    card = db.get(Card, payload.id)
    values = {**(admin_card(db, card) if card else {}), **payload.model_dump()}
    row = save_card(db, admin, CardDraft.model_validate(values), card.id if card else None)
    db.commit()
    return success(admin_card(db, row))


@router.patch("/users/{user_id}/status")
def patch_user_status(
    user_id: str,
    payload: UserStatusPatch,
    admin: User = Depends(current_admin),
    db: Session = Depends(get_db),
) -> dict:
    from app.modules.admin.catalog_service import permit

    permit(admin, "users", "edit")
    user = db.get(User, user_id)
    if user is None:
        raise DomainError("USER_NOT_FOUND", "用户不存在", 404)
    if user.role != "user":
        raise DomainError("PROTECTED_ACCOUNT", "此入口不允许修改管理员账号", 422)
    before = {"is_active": user.is_active}
    user.is_active = payload.is_active
    _audit(
        db, admin.id, "user.status.patch", "user", user.id, before, {"is_active": user.is_active}
    )
    db.commit()
    return success({"id": user.id, "is_active": user.is_active})


@router.get("/scan/feedback")
def list_feedback(admin: User = Depends(current_admin), db: Session = Depends(get_db)) -> dict:
    items = db.scalars(select(ScanFeedback).order_by(ScanFeedback.created_at.desc())).all()
    return success(
        {
            "items": [
                {
                    "id": item.id,
                    "session_id": item.scan_session_id,
                    "detected_card_id": item.detected_card_id,
                    "status": item.status,
                    "payload": item.payload,
                }
                for item in items
            ]
        }
    )


@router.patch("/scan/feedback/{feedback_id}")
def patch_feedback(
    feedback_id: str,
    payload: FeedbackStatusPatch,
    admin: User = Depends(current_admin),
    db: Session = Depends(get_db),
) -> dict:
    item = db.get(ScanFeedback, feedback_id)
    if item is None:
        raise DomainError("FEEDBACK_NOT_FOUND", "反馈不存在", 404)
    before = {"status": item.status}
    item.status = payload.status
    _audit(
        db,
        admin.id,
        "scan.feedback.patch",
        "scan_feedback",
        item.id,
        before,
        {"status": item.status},
    )
    db.commit()
    return success({"id": item.id, "status": item.status})


@router.get("/moderation/reports")
def list_reports(admin: User = Depends(current_admin), db: Session = Depends(get_db)) -> dict:
    from app.modules.admin.catalog_service import permit

    permit(admin, "reports")
    reports = db.scalars(select(Report).order_by(Report.created_at.desc())).all()
    return success(
        {
            "items": [
                {
                    "id": item.id,
                    "target_type": item.target_type,
                    "target_id": item.target_id,
                    "reason": item.reason,
                    "status": item.status,
                }
                for item in reports
            ]
        }
    )


@router.post("/worker/social-posts:upsert")
def ingest_social_posts(
    payload: WorkerPostBatch, worker: str = Depends(verify_worker), db: Session = Depends(get_db)
) -> dict:
    created = 0
    updated = 0
    for item in payload.items:
        post = db.scalar(
            select(SocialPost).where(
                SocialPost.platform == item.platform,
                SocialPost.original_post_id == item.original_post_id,
            )
        )
        values = item.model_dump()
        values["posted_at"] = values.pop("post_time")
        values["fetched_at"] = values.pop("fetch_time")
        if post is None:
            db.add(SocialPost(**values))
            created += 1
        else:
            for key, value in values.items():
                setattr(post, key, value)
            updated += 1
    _audit(
        db,
        worker,
        "social_posts.batch_upsert",
        "social_post",
        "batch",
        None,
        {"created": created, "updated": updated},
    )
    db.commit()
    return success({"created": created, "updated": updated})
