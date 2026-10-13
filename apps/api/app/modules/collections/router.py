from __future__ import annotations

from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.common.response import DomainError, success
from app.common.serializers import album_payload, photo_payload
from app.core.database import get_db
from app.core.security import current_user
from app.integrations.storage import get_storage
from app.models import (
    Card,
    CardAlbum,
    ProfilePhoto,
    User,
    UserCollectionItem,
    UserWishlistItem,
    new_id,
)
from app.modules.albums import service as album_service
from app.modules.albums.schemas import AlbumCreate as DigitalAlbumCreate
from app.modules.albums.schemas import AlbumPatch
from app.modules.collections.schemas import AlbumCardsUpdate, AlbumCreate, QuantityUpdate

router = APIRouter(tags=["Collection"])


def _ensure_card(db: Session, card_id: str) -> None:
    if db.get(Card, card_id) is None:
        raise DomainError("CARD_NOT_FOUND", "小卡不存在", 404)


@router.get("/me/collection")
def get_collection(user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    owned = db.scalars(
        select(UserCollectionItem).where(UserCollectionItem.user_id == user.id)
    ).all()
    wished = db.scalars(
        select(UserWishlistItem.card_id).where(UserWishlistItem.user_id == user.id)
    ).all()
    return success(
        {"owned": {item.card_id: item.quantity for item in owned}, "wishlist": list(wished)}
    )


@router.put("/me/collection/{card_id}")
def set_quantity(
    card_id: str,
    payload: QuantityUpdate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    _ensure_card(db, card_id)
    item = db.scalar(
        select(UserCollectionItem).where(
            UserCollectionItem.user_id == user.id, UserCollectionItem.card_id == card_id
        )
    )
    if payload.quantity == 0 and item:
        db.delete(item)
    elif item:
        item.quantity = payload.quantity
    elif payload.quantity > 0:
        db.add(UserCollectionItem(user_id=user.id, card_id=card_id, quantity=payload.quantity))
    db.commit()
    return success({"card_id": card_id, "quantity": payload.quantity})


@router.post("/me/collection/{card_id}/increment")
def increment_quantity(
    card_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    _ensure_card(db, card_id)
    item = db.scalar(
        select(UserCollectionItem).where(
            UserCollectionItem.user_id == user.id, UserCollectionItem.card_id == card_id
        )
    )
    if item:
        item.quantity += 1
    else:
        item = UserCollectionItem(user_id=user.id, card_id=card_id, quantity=1)
        db.add(item)
    db.commit()
    return success({"card_id": card_id, "quantity": item.quantity})


@router.put("/me/wishlist/{card_id}")
def add_wishlist(
    card_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    _ensure_card(db, card_id)
    exists = db.scalar(
        select(UserWishlistItem).where(
            UserWishlistItem.user_id == user.id, UserWishlistItem.card_id == card_id
        )
    )
    if exists is None:
        db.add(UserWishlistItem(user_id=user.id, card_id=card_id))
        db.commit()
    return success({"card_id": card_id, "wished": True})


@router.delete("/me/wishlist/{card_id}")
def remove_wishlist(
    card_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    db.execute(
        delete(UserWishlistItem).where(
            UserWishlistItem.user_id == user.id, UserWishlistItem.card_id == card_id
        )
    )
    db.commit()
    return success({"card_id": card_id, "wished": False})


@router.get("/me/card-albums")
def get_albums(user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    albums = db.scalars(
        select(CardAlbum)
        .where(CardAlbum.user_id == user.id, CardAlbum.status != "DELETED")
        .order_by(CardAlbum.updated_at.desc())
    ).all()
    return success({"items": [album_payload(db, album, user) for album in albums]})


@router.post("/me/card-albums")
def create_album(
    payload: AlbumCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    album = album_service.create(db, user, DigitalAlbumCreate(name=payload.name))
    db.commit()
    db.refresh(album)
    return success(album_payload(db, album, user))


@router.put("/me/card-albums/{album_id}/cards")
def put_album_cards(
    album_id: str,
    payload: AlbumCardsUpdate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    album = album_service.get_album(db, album_id, user, edit=True)
    if payload.revision is None:
        raise DomainError(
            "ALBUM_REVISION_REQUIRED", "更新卡册需要版本号，请使用新版相册编辑器", 409
        )
    card_ids = list(dict.fromkeys(payload.card_ids))
    pages = [
        {
            "id": new_id("page"),
            "grid_count": len(card_ids[i : i + 9]),
            "slots": [
                {"id": new_id("slot"), "card_id": card_id} for card_id in card_ids[i : i + 9]
            ],
        }
        for i in range(0, len(card_ids), 9)
    ]
    album_service.patch(
        db,
        album,
        user,
        AlbumPatch(
            revision=payload.revision, pages=pages, confirm_removal=True, confirm_duplicates=True
        ),
    )
    db.commit()
    return success(album_payload(db, album, user))


@router.get("/me/profile-photos")
def get_profile_photos(user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    photos = db.scalars(
        select(ProfilePhoto)
        .where(ProfilePhoto.user_id == user.id)
        .order_by(ProfilePhoto.created_at.desc())
    ).all()
    return success({"items": [photo_payload(photo) for photo in photos]})


@router.post("/me/profile-photos")
async def upload_profile_photo(
    image: UploadFile = File(...), user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    content = await image.read()
    if not content:
        raise DomainError("EMPTY_FILE", "图片不能为空")
    url = get_storage().save_bytes(content, image.filename or "photo.jpg", f"profiles/{user.id}")
    photo = ProfilePhoto(user_id=user.id, image_url=url)
    db.add(photo)
    db.commit()
    db.refresh(photo)
    return success(photo_payload(photo))
