from __future__ import annotations

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.common.response import DomainError
from app.common.serializers import profile_payload, relationship_status
from app.models import Idol, User, UserFollow, UserIdol
from app.modules.users.schemas import FavoriteUpdate, ProfilePatch

PRIVACY_FIELDS = {
    "collection_visible",
    "likes_visible",
    "albums_visible",
    "photos_visible",
    "following_list_visible",
    "followers_list_visible",
    "favorites_visible",
    "discoverable",
}


def update_profile(db: Session, user: User, payload: ProfilePatch) -> dict[str, object]:
    for field in ("display_name", "bio", "avatar_url", "weibo_visible"):
        value = getattr(payload, field)
        if value is not None:
            setattr(user, field, value)
    if payload.privacy:
        for field, value in payload.privacy.model_dump(exclude_none=True).items():
            if field in PRIVACY_FIELDS:
                setattr(user, field, value)
    db.commit()
    db.refresh(user)
    return profile_payload(db, user, user)


def update_favorites(db: Session, user: User, payload: FavoriteUpdate) -> list[str]:
    unique_ids = list(dict.fromkeys(payload.idol_ids))
    if payload.primary_idol_id and payload.primary_idol_id not in unique_ids:
        raise DomainError("INVALID_PRIMARY_IDOL", "请先将该艺人加入本命，再点亮星星")
    if len(unique_ids) > 20:
        raise DomainError("FAVORITE_LIMIT_REACHED", "最多设置 20 个本命")
    known = set(db.scalars(select(Idol.id).where(Idol.id.in_(unique_ids))).all())
    if known != set(unique_ids):
        raise DomainError("IDOL_NOT_FOUND", "部分本命不存在", 404)
    if payload.primary_idol_id:
        unique_ids.remove(payload.primary_idol_id)
        unique_ids.insert(0, payload.primary_idol_id)
    user.primary_idol_id = payload.primary_idol_id
    db.execute(
        delete(UserIdol).where(UserIdol.user_id == user.id, UserIdol.relation_type == "favorite")
    )
    db.add_all(
        [
            UserIdol(user_id=user.id, idol_id=idol_id, relation_type="favorite", priority=i)
            for i, idol_id in enumerate(unique_ids)
        ]
    )
    db.commit()
    return unique_ids


def toggle_follow(db: Session, user: User, target: User, follow: bool) -> dict[str, object]:
    if user.id == target.id:
        raise DomainError("CANNOT_FOLLOW_SELF", "不能关注自己")
    row = db.scalar(
        select(UserFollow).where(
            UserFollow.follower_id == user.id, UserFollow.following_id == target.id
        )
    )
    if follow and row is None:
        db.add(UserFollow(follower_id=user.id, following_id=target.id))
    elif not follow and row is not None:
        db.delete(row)
    db.commit()
    follower_count = (
        db.scalar(
            select(func.count()).select_from(UserFollow).where(UserFollow.following_id == target.id)
        )
        or 0
    )
    return {
        "relation_status": relationship_status(db, user.id, target.id),
        "followers_count": follower_count,
    }


def relation_users(
    db: Session, owner: User, viewer: User, relation_type: str
) -> list[dict[str, object]]:
    if owner.id != viewer.id:
        visible = (
            owner.followers_list_visible
            if relation_type == "followers"
            else owner.following_list_visible
        )
        if not visible:
            raise DomainError("RELATION_LIST_PRIVATE", "对方暂未公开该列表", 403)
    id_column = UserFollow.follower_id if relation_type == "followers" else UserFollow.following_id
    condition = (
        UserFollow.following_id == owner.id
        if relation_type == "followers"
        else UserFollow.follower_id == owner.id
    )
    ids = db.scalars(select(id_column).where(condition)).all()
    users = (
        db.scalars(select(User).where(User.id.in_(ids), User.is_active.is_(True))).all()
        if ids
        else []
    )
    return [profile_payload(db, item, viewer) for item in users]
