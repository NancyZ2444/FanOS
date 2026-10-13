from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.common.response import success
from app.core.database import get_db
from app.core.security import current_user
from app.models import DailyCardDraw, SocialPost, User, UserCollectionItem, UserIdol
from app.modules.admin.public_operations import active_announcements
from app.modules.social_feed.service import post_payload

router = APIRouter(prefix="/home", tags=["Home"])


@router.get("")
def home(user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    favorite_ids = list(
        db.scalars(
            select(UserIdol.idol_id).where(UserIdol.user_id == user.id).order_by(UserIdol.priority)
        ).all()
    )
    query = select(SocialPost).where(SocialPost.is_available.is_(True))
    if favorite_ids:
        query = query.where(SocialPost.idol_id.in_(favorite_ids))
    posts = db.scalars(query.order_by(SocialPost.posted_at.desc()).limit(5)).all()
    owned_count = (
        db.scalar(
            select(func.count())
            .select_from(UserCollectionItem)
            .where(UserCollectionItem.user_id == user.id)
        )
        or 0
    )
    used_draws = (
        db.scalar(
            select(func.count())
            .select_from(DailyCardDraw)
            .where(DailyCardDraw.user_id == user.id, DailyCardDraw.draw_date == date.today())
        )
        or 0
    )
    return success(
        {
            "favorite_idol_ids": favorite_ids,
            "owned_count": owned_count,
            "daily_card_remaining": max(0, 3 - used_draws),
            "idol_feed": [post_payload(db, post) for post in posts],
            "announcements": active_announcements(db)[:1],
        }
    )
