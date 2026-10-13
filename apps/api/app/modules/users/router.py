from io import BytesIO

from fastapi import APIRouter, Depends, File, Query, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.response import DomainError, success
from app.common.serializers import profile_payload
from app.core.database import get_db
from app.core.security import current_user
from app.integrations.storage import get_storage
from app.models import Group, Idol, User
from app.modules.users import service
from app.modules.users.schemas import (
    FavoriteUpdate,
    NameDisplayPatch,
    NameRemarkPatch,
    ProfilePatch,
)

router = APIRouter(tags=["Users"])


def name_preferences(user: User) -> dict:
    return {
        "mode": "official",
        "aliases": {"groups": {}, "idols": {}},
        **(user.name_preferences or {}),
    }


@router.get("/me/name-preferences")
def get_name_preferences(user: User = Depends(current_user)) -> dict:
    return success(name_preferences(user))


@router.patch("/me/name-preferences")
def patch_name_preferences(
    payload: NameDisplayPatch, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    user.name_preferences = {**name_preferences(user), "mode": payload.mode}
    db.commit()
    return success(name_preferences(user))


@router.put("/me/name-preferences/{kind}/{entity_id}")
def put_name_remark(
    kind: str,
    entity_id: str,
    payload: NameRemarkPatch,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    model = {"groups": Group, "idols": Idol}.get(kind)
    if model is None or db.get(model, entity_id) is None:
        raise DomainError("ENTITY_NOT_FOUND", "艺人或组合不存在", 404)
    preferences = name_preferences(user)
    aliases = {**preferences["aliases"]}
    names = {**aliases.get(kind, {})}
    if payload.remark:
        names[entity_id] = payload.remark
    else:
        names.pop(entity_id, None)
    aliases[kind] = names
    user.name_preferences = {**preferences, "aliases": aliases}
    db.commit()
    return success(name_preferences(user))


@router.post("/me/profile/images/{kind}")
async def upload_profile_image(
    kind: str,
    image: UploadFile = File(...),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    if kind not in {"avatar", "background"}:
        raise DomainError("INVALID_IMAGE_KIND", "不支持的主页图片类型")
    content = await image.read(10 * 1024 * 1024 + 1)
    if len(content) > 10 * 1024 * 1024:
        raise DomainError("IMAGE_TOO_LARGE", "图片不能超过 10 MB", 413)
    try:
        with Image.open(BytesIO(content)) as source:
            if source.width * source.height > 24_000_000:
                raise DomainError("IMAGE_TOO_LARGE", "图片尺寸过大", 413)
            photo = ImageOps.exif_transpose(source).convert("RGB")
            photo.thumbnail((2400, 2400))
            output = BytesIO()
            photo.save(output, format="JPEG", quality=90)
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
        raise DomainError("INVALID_IMAGE", "请选择有效的图片") from exc
    url = get_storage().save_bytes(output.getvalue(), f"{kind}.jpg", f"profiles/{user.id}")
    setattr(user, f"{kind}_url", url)
    db.commit()
    return success({"image_url": url})


@router.delete("/me/profile/images/{kind}")
def remove_profile_image(
    kind: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    if kind not in {"avatar", "background"}:
        raise DomainError("INVALID_IMAGE_KIND", "不支持的主页图片类型")
    setattr(user, f"{kind}_url", None)
    db.commit()
    # Retain the old stored file: changing a cover must not delete shared media.
    return success({"image_url": None})


@router.get("/me/profile")
def my_profile(user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    return success(profile_payload(db, user, user))


@router.patch("/me/profile")
def patch_profile(
    payload: ProfilePatch, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success(service.update_profile(db, user, payload))


@router.put("/me/favorites")
def put_favorites(
    payload: FavoriteUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success({"idol_ids": service.update_favorites(db, user, payload)})


@router.get("/users/search")
def search_users(
    q: str = Query(min_length=1, max_length=40),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    users = db.scalars(
        select(User)
        .where(
            User.display_name.ilike(f"%{q}%"), User.discoverable.is_(True), User.is_active.is_(True)
        )
        .limit(30)
    ).all()
    return success({"items": [profile_payload(db, item, user) for item in users]})


def _target(db: Session, user_id: str) -> User:
    target = db.get(User, user_id)
    if target is None or not target.is_active:
        raise DomainError("USER_NOT_FOUND", "该用户不存在或已注销", 404)
    return target


@router.get("/users/{user_id}")
def public_profile(
    user_id: str, viewer: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success(profile_payload(db, _target(db, user_id), viewer))


@router.put("/users/{user_id}/follow")
def follow_user(
    user_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success(service.toggle_follow(db, user, _target(db, user_id), True))


@router.delete("/users/{user_id}/follow")
def unfollow_user(
    user_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success(service.toggle_follow(db, user, _target(db, user_id), False))


@router.get("/users/{user_id}/following")
def following(
    user_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success({"items": service.relation_users(db, _target(db, user_id), user, "following")})


@router.get("/users/{user_id}/followers")
def followers(
    user_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success({"items": service.relation_users(db, _target(db, user_id), user, "followers")})
