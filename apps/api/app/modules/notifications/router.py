from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.common.response import success
from app.core.database import get_db
from app.core.security import current_user
from app.models import NotificationSetting, User

router = APIRouter(prefix="/notifications", tags=["Notifications"])


def _setting(db: Session, user: User) -> NotificationSetting:
    setting = db.get(NotificationSetting, user.id)
    if setting is None:
        setting = NotificationSetting(user_id=user.id)
        db.add(setting)
        db.commit()
        db.refresh(setting)
    return setting


def _payload(setting: NotificationSetting) -> dict[str, bool]:
    return {
        "enabled": setting.idol_feed_enabled,
        "primary_idol_first": setting.primary_idol_first,
        "push_enabled": setting.push_enabled,
    }


@router.get("/settings/idol-feed")
def get_settings(user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    return success(_payload(_setting(db, user)))


@router.patch("/settings/idol-feed")
def patch_settings(
    payload: dict, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    setting = _setting(db, user)
    mapping = {
        "enabled": "idol_feed_enabled",
        "primary_idol_first": "primary_idol_first",
        "push_enabled": "push_enabled",
    }
    for key, field in mapping.items():
        if key in payload and isinstance(payload[key], bool):
            setattr(setting, field, payload[key])
    db.commit()
    return success(_payload(setting))
