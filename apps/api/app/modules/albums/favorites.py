"""Saved albums are references. Publishing a folder never publishes its source albums."""

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.album_models import AlbumFavoriteGroup, AlbumFavoritePlacement, AlbumReaction
from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_user, optional_user
from app.models import CardAlbum, User
from app.modules.albums import service

router = APIRouter(tags=["Album Favorite Groups"])


class GroupInput(BaseModel):
    name: str = Field(min_length=1, max_length=40)
    is_public: bool = False

    @field_validator("name")
    @classmethod
    def clean_name(cls, value):
        value = value.strip()
        if not value or value in {"全部", "未分组"}:
            raise ValueError("请填写其他分组名称")
        return value


class FavoriteInput(BaseModel):
    group_id: str | None = None


def owned_group(db, user, group_id):
    group = db.get(AlbumFavoriteGroup, group_id)
    if not group or group.user_id != user.id:
        raise DomainError("FAVORITE_GROUP_NOT_FOUND", "收藏分组不存在", 404)
    return group


def assign_group(db, reaction, user, group_id):
    if group_id:
        owned_group(db, user, group_id)
    placement = db.get(AlbumFavoritePlacement, reaction.id)
    if placement:
        if group_id:
            placement.group_id = group_id
        else:
            db.delete(placement)
    elif group_id:
        db.add(AlbumFavoritePlacement(reaction_id=reaction.id, group_id=group_id))


def group_payload(group, count=0):
    return {"id": group.id, "name": group.name, "is_public": group.is_public, "album_count": count}


def visible_owner(db, user_id, viewer):
    owner = db.get(User, user_id)
    if not owner or not owner.is_active:
        raise DomainError("USER_NOT_FOUND", "用户不存在", 404)
    is_owner = viewer is not None and viewer.id == owner.id
    return owner, is_owner, is_owner or owner.albums_visible


def favorite_query(owner_id):
    return (
        select(AlbumReaction)
        .join(CardAlbum, CardAlbum.id == AlbumReaction.album_id)
        .outerjoin(AlbumFavoritePlacement, AlbumFavoritePlacement.reaction_id == AlbumReaction.id)
        .outerjoin(AlbumFavoriteGroup, AlbumFavoriteGroup.id == AlbumFavoritePlacement.group_id)
        .where(
            AlbumReaction.user_id == owner_id,
            AlbumReaction.kind == "FAVORITE",
            CardAlbum.user_id != owner_id,
        )
    )


def public_only(query):
    return query.where(
        AlbumFavoriteGroup.is_public.is_(True),
        CardAlbum.is_public.is_(True),
        CardAlbum.status == "PUBLISHED",
        CardAlbum.is_moderated.is_(False),
        CardAlbum.user_id.in_(select(User.id).where(User.is_active.is_(True))),
    )


@router.get("/users/{user_id}/album-favorite-groups")
def groups(
    user_id: str, viewer: User | None = Depends(optional_user), db: Session = Depends(get_db)
):
    if user_id == "me":
        if not viewer:
            raise DomainError("AUTH_REQUIRED", "请先登录", 401)
        user_id = viewer.id
    owner, is_owner, visible = visible_owner(db, user_id, viewer)
    if not visible:
        return success({"items": [], "ungrouped_count": 0})
    query = select(AlbumFavoriteGroup).where(AlbumFavoriteGroup.user_id == owner.id)
    if not is_owner:
        query = query.where(AlbumFavoriteGroup.is_public.is_(True))
    result = []
    for group in db.scalars(query.order_by(AlbumFavoriteGroup.created_at, AlbumFavoriteGroup.id)):
        saved = favorite_query(owner.id).where(AlbumFavoriteGroup.id == group.id)
        if not is_owner:
            saved = public_only(saved)
        count = db.scalar(select(func.count()).select_from(saved.subquery()))
        result.append(group_payload(group, count))
    ungrouped = (
        db.scalar(
            select(func.count()).select_from(
                favorite_query(owner.id)
                .where(AlbumFavoritePlacement.reaction_id.is_(None))
                .subquery()
            )
        )
        if is_owner
        else 0
    )
    return success({"items": result, "ungrouped_count": ungrouped})


@router.post("/users/me/album-favorite-groups")
def create_group(
    data: GroupInput, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    service.lock_quota(db, user)
    if db.scalar(
        select(AlbumFavoriteGroup.id).where(
            AlbumFavoriteGroup.user_id == user.id,
            func.lower(AlbumFavoriteGroup.name) == data.name.lower(),
        )
    ):
        raise DomainError("FAVORITE_GROUP_DUPLICATE", "已存在同名收藏分组", 409)
    group = AlbumFavoriteGroup(user_id=user.id, **data.model_dump())
    db.add(group)
    db.commit()
    return success(group_payload(group))


@router.put("/users/me/album-favorite-groups/{group_id}")
def update_group(
    group_id: str,
    data: GroupInput,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    service.lock_quota(db, user)
    group = owned_group(db, user, group_id)
    if db.scalar(
        select(AlbumFavoriteGroup.id).where(
            AlbumFavoriteGroup.user_id == user.id,
            AlbumFavoriteGroup.id != group_id,
            func.lower(AlbumFavoriteGroup.name) == data.name.lower(),
        )
    ):
        raise DomainError("FAVORITE_GROUP_DUPLICATE", "已存在同名收藏分组", 409)
    group.name, group.is_public = data.name, data.is_public
    db.commit()
    return success(group_payload(group))


@router.get("/users/{user_id}/favorite-albums")
def saved_albums(
    user_id: str,
    group_id: str | None = None,
    offset: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=50),
    viewer: User | None = Depends(optional_user),
    db: Session = Depends(get_db),
):
    owner, is_owner, visible = visible_owner(db, user_id, viewer)
    if not visible:
        return success({"items": [], "next_offset": None})
    query = favorite_query(owner.id)
    if not is_owner:
        query = public_only(query)
    if group_id == "ungrouped":
        query = query.where(AlbumFavoritePlacement.reaction_id.is_(None))
    elif group_id:
        query = query.where(AlbumFavoriteGroup.id == group_id)
    rows = db.scalars(
        query.order_by(AlbumReaction.created_at.desc(), AlbumReaction.id.desc())
        .offset(offset)
        .limit(limit + 1)
    ).all()
    items = []
    for reaction in rows[:limit]:
        try:
            item = service.payload(
                db, service.get_album(db, reaction.album_id, viewer), viewer, summary=True
            )
        except DomainError:
            if not is_owner:
                continue
            item = {
                "id": reaction.album_id,
                "name": "卡册暂不可访问",
                "unavailable": True,
                "favorited": True,
                "card_count": 0,
                "page_count": 0,
            }
        placement = db.get(AlbumFavoritePlacement, reaction.id)
        item.update(
            favorited_at=reaction.created_at.isoformat(),
            favorite_group_id=placement.group_id if placement else None,
        )
        items.append(item)
    return success({"items": items, "next_offset": offset + limit if len(rows) > limit else None})


@router.put("/users/me/favorite-albums/{album_id}/group")
def move_favorite(
    album_id: str,
    data: FavoriteInput,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    service.lock_quota(db, user)
    reaction = db.scalar(
        select(AlbumReaction).where(
            AlbumReaction.album_id == album_id,
            AlbumReaction.user_id == user.id,
            AlbumReaction.kind == "FAVORITE",
        )
    )
    if not reaction:
        raise DomainError("ALBUM_NOT_FAVORITED", "请先收藏卡册", 404)
    assign_group(db, reaction, user, data.group_id)
    db.commit()
    return success({"group_id": data.group_id})
