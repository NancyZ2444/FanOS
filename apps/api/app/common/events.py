"""Transactional event helpers shared by current and future modules."""

from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from app.future_models import OutboxEvent


def enqueue_outbox(
    db: Session,
    *,
    event_type: str,
    aggregate_type: str,
    aggregate_id: str,
    payload: dict[str, Any],
    event_version: int = 1,
) -> OutboxEvent:
    """Add an event to the caller's transaction without committing it."""

    event = OutboxEvent(
        event_type=event_type,
        event_version=event_version,
        aggregate_type=aggregate_type,
        aggregate_id=aggregate_id,
        payload=payload,
    )
    db.add(event)
    return event
