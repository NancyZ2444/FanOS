from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import (
    Card,
    CardAlbum,
    CatalogAlbum,
    CatalogEvent,
    CatalogMerchandise,
    Group,
    Idol,
    ProfilePhoto,
    User,
    UserCollectionItem,
    UserFollow,
    UserIdol,
    UserWishlistItem,
)
from app.modules.catalog.media_import import managed_thumbnail, public_image


def card_payload(db: Session, card: Card) -> dict[str, object]:
    idol = db.get(Idol, card.idol_id) if card.idol_id else None
    group = db.get(Group, card.group_id) if card.group_id else None
    from app.modules.catalog.tags import entity_tags
    from app.modules.catalog.taxonomy_models import CatalogOther

    metadata = card.admin_data or {}
    source_model = {
        "ALBUM": CatalogAlbum,
        "EVENT": CatalogEvent,
        "OTHER": CatalogOther,
    }.get(metadata.get("source_entity_type"))
    source_entity = (
        db.get(source_model, metadata["source_entity_id"])
        if source_model and metadata.get("source_entity_id")
        else None
    )
    return {
        "id": card.id,
        "card_number": card.card_number,
        "title": card.title,
        "title_en": card.title_en,
        "title_ko": card.title_ko,
        "title_translated": card.title_translated,
        "idol_id": card.idol_id or "",
        "idol_name": idol.name if idol else "团体小卡",
        "group_id": card.group_id,
        "group_name": group.name if group else "",
        "source": source_entity.name if source_entity else card.source,
        "card_type": card.card_type,
        "version": card.version,
        "release_date": card.release_date,
        "region": card.region,
        "color_start": card.color_start,
        "color_end": card.color_end,
        "image_url": public_image(card.image_url),
        "thumbnail_url": managed_thumbnail(metadata, card.image_url),
        "status": card.status,
        "back_image_url": public_image((card.admin_data or {}).get("back_image_url")),
        **{
            key: metadata[key]
            for key in (
                "source_entity_id",
                "source_entity_type",
                "tags",
                "rarity",
                "is_group_pc",
                "is_double_sided",
                "is_limited",
                "is_official",
                "has_ar",
                "ar_type",
                "ar_resource",
                "ar_status",
                "ar_preview",
                "entity_version_id",
                "edition",
            )
            if key in metadata
        },
        **entity_tags(db, "cards", card.id),
    }


def catalog_album_payload(album: CatalogAlbum) -> dict[str, object]:
    return {
        "id": album.id,
        "name": album.name,
        "name_en": album.name_en,
        "name_ko": album.name_ko,
        "name_translated": album.name_translated,
        "artist_name": album.artist_name,
        "group_id": album.group_id,
        "release_date": album.release_date,
        "album_type": album.album_type,
        "versions": album.versions,
        "description": album.description,
        "color_start": album.color_start,
        "color_end": album.color_end,
        "image_url": public_image(album.image_url),
        "front_image_url": public_image(album.front_image_url or album.image_url),
        "back_image_url": public_image(album.back_image_url),
    }


def catalog_event_payload(event: CatalogEvent) -> dict[str, object]:
    return {
        "id": event.id,
        "name": event.name,
        "name_en": event.name_en,
        "name_ko": event.name_ko,
        "name_translated": event.name_translated,
        "artist_name": event.artist_name,
        "group_id": event.group_id,
        "event_type": event.event_type,
        "start_date": event.start_date,
        "region": event.region,
        "city": event.city,
        "platform": event.platform,
        "venue": event.venue,
        "parent_event_id": event.parent_event_id,
        "is_online": event.is_online,
        "description": event.description,
        "color_start": event.color_start,
        "color_end": event.color_end,
        "image_url": public_image(event.image_url),
    }


def catalog_merchandise_payload(item: CatalogMerchandise) -> dict[str, object]:
    return {
        "id": item.id,
        "name": item.name,
        "name_en": item.name_en,
        "name_ko": item.name_ko,
        "name_translated": item.name_translated,
        "artist_name": item.artist_name,
        "group_id": item.group_id,
        "type": item.type,
        "source": item.source,
        "release_date": item.release_date,
        "region": item.region,
        "description": item.description,
        "color_start": item.color_start,
        "color_end": item.color_end,
        "image_url": public_image(item.image_url),
    }


def privacy_payload(user: User) -> dict[str, bool]:
    return {
        "collection_visible": user.collection_visible,
        "likes_visible": user.likes_visible,
        "albums_visible": user.albums_visible,
        "photos_visible": user.photos_visible,
        "following_list_visible": user.following_list_visible,
        "followers_list_visible": user.followers_list_visible,
        "favorites_visible": user.favorites_visible,
        "discoverable": user.discoverable,
    }


def relationship_status(db: Session, viewer_id: str, target_id: str) -> str:
    following = db.scalar(
        select(UserFollow.id).where(
            UserFollow.follower_id == viewer_id, UserFollow.following_id == target_id
        )
    )
    follows_you = db.scalar(
        select(UserFollow.id).where(
            UserFollow.follower_id == target_id, UserFollow.following_id == viewer_id
        )
    )
    if following and follows_you:
        return "mutual"
    if following:
        return "following"
    if follows_you:
        return "follows_you"
    return "none"


def social_counts(db: Session, user_id: str) -> tuple[int, int]:
    """Count the same active accounts returned by the relationship lists."""
    following = db.scalar(
        select(func.count(User.id))
        .join(UserFollow, UserFollow.following_id == User.id)
        .where(UserFollow.follower_id == user_id, User.is_active.is_(True))
    ) or 0
    followers = db.scalar(
        select(func.count(User.id))
        .join(UserFollow, UserFollow.follower_id == User.id)
        .where(UserFollow.following_id == user_id, User.is_active.is_(True))
    ) or 0
    return following, followers


def profile_payload(db: Session, user: User, viewer: User | None = None) -> dict[str, object]:
    from app.auth_models import TrustedIdentity
    from app.modules.auth.service import user_payload

    identity = db.scalar(
        select(TrustedIdentity).where(
            TrustedIdentity.user_id == user.id, TrustedIdentity.provider == "weibo"
        )
    )
    auth_flags = user_payload(user, db)
    weibo_profile_url = identity.profile_url if identity and user.weibo_visible else None
    is_self = viewer is not None and viewer.id == user.id
    favorite_rows = db.scalars(
        select(UserIdol)
        .where(UserIdol.user_id == user.id, UserIdol.relation_type == "favorite")
        .order_by(UserIdol.priority)
    ).all()
    favorite_ids = [row.idol_id for row in favorite_rows]
    owned = db.scalars(
        select(UserCollectionItem).where(UserCollectionItem.user_id == user.id)
    ).all()
    liked_ids = list(
        db.scalars(
            select(UserWishlistItem.card_id).where(UserWishlistItem.user_id == user.id)
        ).all()
    )
    albums = db.scalars(
        select(CardAlbum).where(CardAlbum.user_id == user.id, CardAlbum.status != "DELETED")
    ).all()
    photos = db.scalars(select(ProfilePhoto).where(ProfilePhoto.user_id == user.id)).all()
    following_count, followers_count = social_counts(db, user.id)
    privacy = privacy_payload(user)
    visible_albums = [
        row
        for row in albums
        if is_self
        or (
            row.is_public
            and row.status == "PUBLISHED"
            and not row.is_moderated
            and not row.publication_blocked
        )
    ]
    visible_photos = [row for row in photos if is_self or row.is_public]
    return {
        "id": user.id,
        "display_name": user.display_name,
        "bio": user.bio,
        "avatar_url": user.avatar_url,
        "background_url": user.background_url,
        "level": user.level,
        "experience": user.experience,
        "next_level_experience": user.next_level_experience,
        "primary_idol_id": user.primary_idol_id
        if user.primary_idol_id in favorite_ids and (is_self or user.favorites_visible)
        else None,
        "favorite_idol_ids": favorite_ids if is_self or user.favorites_visible else [],
        "following_count": following_count,
        "followers_count": followers_count,
        "following_list_visible": user.following_list_visible,
        "followers_list_visible": user.followers_list_visible,
        "owned": (
            {row.card_id: row.quantity for row in owned}
            if is_self or user.collection_visible
            else None
        ),
        "liked_card_ids": liked_ids if is_self or user.likes_visible else None,
        "album_count": len(visible_albums) if is_self or user.albums_visible else None,
        "photo_count": len(photos) if is_self or user.photos_visible else None,
        "albums": [album_payload(db, row, viewer) for row in visible_albums]
        if is_self or user.albums_visible
        else None,
        "photos": [photo_payload(row) for row in visible_photos]
        if is_self or user.photos_visible
        else None,
        "weibo_name": identity.display_name if identity and user.weibo_visible else None,
        "weibo_profile_url": weibo_profile_url,
        "weibo_url": weibo_profile_url,
        "onboarding_completed": auth_flags["onboarding_completed"],
        "password_setup_required": auth_flags["password_setup_required"] if is_self else None,
        "privacy": privacy if is_self else None,
        "relation_status": relationship_status(db, viewer.id, user.id)
        if viewer and not is_self
        else None,
    }


def album_payload(db: Session, album: CardAlbum, viewer: User | None = None) -> dict[str, object]:
    from app.modules.albums.service import payload

    return payload(db, album, viewer, summary=True)


def photo_payload(photo: ProfilePhoto) -> dict[str, object]:
    return {
        "id": photo.id,
        "image_url": photo.image_url,
        "is_public": photo.is_public,
        "created_at": photo.created_at.isoformat(),
    }
