"""User-facing reads of approved operational content."""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.admin_models import ContentMetadata
from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_user
from app.future_models import NotificationInboxItem
from app.models import User

router = APIRouter(tags=["Operational Content"])


def active_announcements(db: Session) -> list[dict]:
    now = datetime.now(UTC).isoformat()
    rows = db.scalars(
        select(ContentMetadata).where(
            ContentMetadata.entity_type == "announcements", ContentMetadata.status == "PUBLISHED"
        )
    )
    result = [
        {**r.data, "id": r.entity_id}
        for r in rows
        if (not r.data.get("start_time") or r.data["start_time"] <= now)
        and (not r.data.get("end_time") or r.data["end_time"] >= now)
    ]
    return sorted(result, key=lambda r: r.get("priority", 0), reverse=True)


@router.get("/announcements")
def announcements(db: Session = Depends(get_db)) -> dict:
    return success({"items": active_announcements(db)})


@router.get("/notifications/inbox")
def inbox(user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    rows = db.scalars(
        select(NotificationInboxItem)
        .where(NotificationInboxItem.user_id == user.id)
        .order_by(NotificationInboxItem.created_at.desc())
        .limit(100)
    )
    return success(
        {
            "items": [
                {
                    "id": r.id,
                    "title": r.title,
                    "content": r.body,
                    "category": r.category,
                    "payload": r.payload,
                    "read_at": r.read_at,
                    "created_at": r.created_at,
                }
                for r in rows
            ]
        }
    )


@router.post("/notifications/inbox/{item_id}/read")
def mark_read(
    item_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    row = db.get(NotificationInboxItem, item_id)
    if not row or row.user_id != user.id:
        raise DomainError("NOT_FOUND", "通知不存在", 404)
    row.read_at = row.read_at or datetime.now(UTC)
    db.commit()
    return success({"id": row.id, "read_at": row.read_at})
