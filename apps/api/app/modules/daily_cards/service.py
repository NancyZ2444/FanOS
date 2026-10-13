from __future__ import annotations

from datetime import date
from random import SystemRandom

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.admin_models import ContentMetadata
from app.common.response import DomainError
from app.common.serializers import card_payload
from app.models import Card, DailyCardDraw, User, UserIdol

DAILY_LIMIT = 3


def draw(db: Session, user: User, request_id: str) -> dict[str, object]:
    existing = db.scalar(
        select(DailyCardDraw).where(
            DailyCardDraw.user_id == user.id, DailyCardDraw.request_id == request_id
        )
    )
    if existing:
        return _payload(db, existing)
    today = date.today()
    todays_draws = db.scalars(
        select(DailyCardDraw)
        .where(DailyCardDraw.user_id == user.id, DailyCardDraw.draw_date == today)
        .order_by(DailyCardDraw.draw_index)
    ).all()
    if len(todays_draws) >= DAILY_LIMIT:
        raise DomainError("DAILY_CARD_LIMIT_REACHED", "今日翻卡次数已用完", 409)
    drawn_ids = {item.card_id for item in todays_draws}
    favorite_ids = list(
        db.scalars(
            select(UserIdol.idol_id).where(UserIdol.user_id == user.id).order_by(UserIdol.priority)
        ).all()
    )
    cards = db.scalars(select(Card).where(Card.status == "PUBLISHED").order_by(Card.id)).all()
    pool = db.scalar(
        select(ContentMetadata).where(
            ContentMetadata.entity_type == "daily", ContentMetadata.status == "PUBLISHED"
        )
    )
    weights = pool.data.get("weights", {}) if pool else {}
    if pool:
        cards = [card for card in cards if weights.get(card.id, 0) > 0]
    available = [card for card in cards if card.id not in drawn_ids]
    if not available:
        raise DomainError("DAILY_CARD_POOL_EMPTY", "今日卡池暂无可用卡片", 409)
    preferred = [card for card in available if card.idol_id in favorite_ids]
    candidates = preferred or available
    row = DailyCardDraw(
        user_id=user.id,
        card_id=SystemRandom()
        .choices(candidates, weights=[weights.get(card.id, 1) for card in candidates], k=1)[0]
        .id,
        draw_date=today,
        draw_index=len(todays_draws) + 1,
        request_id=request_id,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _payload(db, row)


def _payload(db: Session, draw: DailyCardDraw) -> dict[str, object]:
    used = (
        db.scalar(
            select(func.count())
            .select_from(DailyCardDraw)
            .where(DailyCardDraw.user_id == draw.user_id, DailyCardDraw.draw_date == draw.draw_date)
        )
        or 0
    )
    return {
        "draw_id": draw.id,
        "card": card_payload(db, db.get(Card, draw.card_id)),
        "remaining_count": max(0, DAILY_LIMIT - used),
    }
