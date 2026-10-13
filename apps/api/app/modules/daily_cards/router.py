from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.common.response import success
from app.core.database import get_db
from app.core.security import current_user
from app.models import User
from app.modules.daily_cards.schemas import DrawRequest
from app.modules.daily_cards.service import draw

router = APIRouter(prefix="/daily-cards", tags=["Daily Card"])


@router.post("/draw")
def draw_daily_card(
    payload: DrawRequest, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success(draw(db, user, payload.draw_request_id))
