from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_admin
from app.future_models import OutboxEvent
from app.models import User
from app.modules.admin.catalog_service import audit, permit
from app.modules.catalog.media_import import EVENT, queue_images, target_data

router = APIRouter(prefix="/admin/console/media", tags=["Catalog Media"])


@router.get("/{kind}/{entity_id}")
def media_status(
    kind: str, entity_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    permit(actor, "catalog")
    events = db.scalars(
        select(OutboxEvent)
        .where(
            OutboxEvent.event_type == EVENT,
            OutboxEvent.aggregate_type == kind,
            OutboxEvent.aggregate_id == entity_id,
        )
        .order_by(OutboxEvent.occurred_at.desc())
    ).all()
    return success(
        {
            "items": [
                {
                    "id": e.id,
                    **e.payload,
                    "attempts": e.publish_attempts,
                    "error": e.last_error,
                }
                for e in events
            ]
        }
    )


@router.post("/{kind}/{entity_id}/queue")
def queue_missing(
    kind: str, entity_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    permit(actor, "catalog", "edit")
    row, _, data = target_data(db, kind, entity_id)
    if row is None:
        raise DomainError("NOT_FOUND", "图鉴对象不存在", 404)
    count = queue_images(db, kind, entity_id, data)
    audit(db, actor, "catalog.media.queue", kind, entity_id, None, {"queued": count})
    db.commit()
    return success({"queued": count})


@router.post("/tasks/{task_id}/retry")
def retry(task_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)):
    permit(actor, "catalog", "edit")
    event = db.scalar(select(OutboxEvent).where(OutboxEvent.id == task_id).with_for_update())
    if event is None or event.event_type != EVENT:
        raise DomainError("NOT_FOUND", "下载任务不存在", 404)
    if event.payload.get("state") not in {"failed", "retrying"}:
        raise DomainError("INVALID_STATE", "仅失败或待重试的任务可以重试", 409)
    event.publish_attempts = 0
    event.last_error = None
    event.payload = {**event.payload, "state": "pending", "next_attempt_at": None}
    audit(
        db,
        actor,
        "catalog.media.retry",
        event.aggregate_type,
        event.aggregate_id,
        None,
        {"task_id": task_id},
    )
    db.commit()
    return success({"queued": True})
