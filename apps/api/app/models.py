from __future__ import annotations

from datetime import UTC, date, datetime
from typing import Any
from uuid import uuid4

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid4().hex}"


def utcnow() -> datetime:
    return datetime.now(UTC)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class User(Base, TimestampMixin):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    phone: Mapped[str | None] = mapped_column(String(32), unique=True)
    display_name: Mapped[str] = mapped_column(String(40))
    bio: Mapped[str] = mapped_column(String(240), default="")
    avatar_url: Mapped[str | None] = mapped_column(String(500))
    background_url: Mapped[str | None] = mapped_column(String(500))
    level: Mapped[int] = mapped_column(Integer, default=1)
    experience: Mapped[int] = mapped_column(Integer, default=0)
    next_level_experience: Mapped[int] = mapped_column(Integer, default=250)
    weibo_visible: Mapped[bool] = mapped_column(Boolean, default=False)
    role: Mapped[str] = mapped_column(String(20), default="user")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    collection_visible: Mapped[bool] = mapped_column(Boolean, default=True)
    likes_visible: Mapped[bool] = mapped_column(Boolean, default=True)
    albums_visible: Mapped[bool] = mapped_column(Boolean, default=True)
    photos_visible: Mapped[bool] = mapped_column(Boolean, default=True)
    following_list_visible: Mapped[bool] = mapped_column(Boolean, default=True)
    followers_list_visible: Mapped[bool] = mapped_column(Boolean, default=True)
    favorites_visible: Mapped[bool] = mapped_column(Boolean, default=True)
    discoverable: Mapped[bool] = mapped_column(Boolean, default=True)
    primary_idol_id: Mapped[str | None] = mapped_column(String(64))
    name_preferences: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)


class UserSocialAccount(Base, TimestampMixin):
    __tablename__ = "user_social_accounts"
    __table_args__ = (UniqueConstraint("platform", "platform_user_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("usa"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    platform: Mapped[str] = mapped_column(String(30))
    platform_user_id: Mapped[str] = mapped_column(String(128))
    display_name: Mapped[str | None] = mapped_column(String(100))
    access_token_encrypted: Mapped[str | None] = mapped_column(Text)


class Group(Base, TimestampMixin):
    __tablename__ = "groups"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True)
    name_en: Mapped[str] = mapped_column(String(180), default="")
    name_ko: Mapped[str] = mapped_column(String(180), default="")
    name_translated: Mapped[str] = mapped_column(String(180), default="")
    company: Mapped[str] = mapped_column(String(120), default="")
    status: Mapped[str] = mapped_column(String(30), default="Active")
    description: Mapped[str] = mapped_column(Text, default="")
    debut_date: Mapped[str] = mapped_column(String(20), default="")
    region: Mapped[str] = mapped_column(String(80), default="")
    color_start: Mapped[int] = mapped_column(BigInteger, default=0xFF8B7CFF)
    color_end: Mapped[int] = mapped_column(BigInteger, default=0xFF3843A8)


class Idol(Base, TimestampMixin):
    __tablename__ = "idols"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    name_en: Mapped[str] = mapped_column(String(180), default="")
    name_ko: Mapped[str] = mapped_column(String(180), default="")
    name_translated: Mapped[str] = mapped_column(String(180), default="")
    initials: Mapped[str] = mapped_column(String(12), default="?")
    bio: Mapped[str] = mapped_column(Text, default="")
    company: Mapped[str] = mapped_column(String(120), default="")
    birth_date: Mapped[str] = mapped_column(String(20), default="")
    region: Mapped[str] = mapped_column(String(80), default="")
    role: Mapped[str] = mapped_column(String(100), default="")
    careers: Mapped[list[dict[str, str]]] = mapped_column(JSON, default=list)
    color_start: Mapped[int] = mapped_column(BigInteger, default=0xFF8B7CFF)
    color_end: Mapped[int] = mapped_column(BigInteger, default=0xFF3843A8)


class GroupMembership(Base, TimestampMixin):
    __tablename__ = "group_memberships"
    __table_args__ = (UniqueConstraint("group_id", "idol_id", "start_date"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("gm"))
    group_id: Mapped[str] = mapped_column(ForeignKey("groups.id"), index=True)
    idol_id: Mapped[str] = mapped_column(ForeignKey("idols.id"), index=True)
    start_date: Mapped[date] = mapped_column(Date, default=date.today)
    end_date: Mapped[date | None] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(30), default="active")


class IdolOfficialAccount(Base, TimestampMixin):
    __tablename__ = "idol_official_accounts"
    __table_args__ = (UniqueConstraint("platform", "platform_account_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("ioa"))
    idol_id: Mapped[str | None] = mapped_column(ForeignKey("idols.id"), index=True)
    group_id: Mapped[str | None] = mapped_column(ForeignKey("groups.id"), index=True)
    platform: Mapped[str] = mapped_column(String(30))
    platform_account_id: Mapped[str] = mapped_column(String(128))
    handle: Mapped[str] = mapped_column(String(120))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class Card(Base, TimestampMixin):
    __tablename__ = "cards"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    card_number: Mapped[str] = mapped_column(
        String(40), unique=True, default=lambda: f"FOS-{uuid4().hex.upper()}"
    )
    title: Mapped[str] = mapped_column(String(180), index=True)
    title_en: Mapped[str] = mapped_column(String(220), default="")
    title_ko: Mapped[str] = mapped_column(String(220), default="")
    title_translated: Mapped[str] = mapped_column(String(220), default="")
    idol_id: Mapped[str | None] = mapped_column(ForeignKey("idols.id"), index=True)
    group_id: Mapped[str | None] = mapped_column(ForeignKey("groups.id"), index=True)
    source: Mapped[str] = mapped_column(String(180))
    card_type: Mapped[str] = mapped_column(String(80))
    version: Mapped[str] = mapped_column(String(100))
    release_date: Mapped[str] = mapped_column(String(20))
    region: Mapped[str] = mapped_column(String(80))
    color_start: Mapped[int] = mapped_column(BigInteger, default=0xFF8B7CFF)
    color_end: Mapped[int] = mapped_column(BigInteger, default=0xFF3843A8)
    image_url: Mapped[str | None] = mapped_column(String(500))
    status: Mapped[str] = mapped_column(String(30), default="PUBLISHED", index=True)
    admin_data: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)


class CatalogAlbum(Base, TimestampMixin):
    __tablename__ = "catalog_albums"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(180), index=True)
    name_en: Mapped[str] = mapped_column(String(180), default="")
    name_ko: Mapped[str] = mapped_column(String(180), default="")
    name_translated: Mapped[str] = mapped_column(String(180), default="")
    artist_name: Mapped[str] = mapped_column(String(180))
    group_id: Mapped[str | None] = mapped_column(ForeignKey("groups.id"), index=True)
    release_date: Mapped[str] = mapped_column(String(20), index=True)
    album_type: Mapped[str] = mapped_column(String(80), index=True)
    versions: Mapped[list[str]] = mapped_column(JSON, default=list)
    description: Mapped[str] = mapped_column(Text, default="")
    color_start: Mapped[int] = mapped_column(BigInteger, default=0xFF8B7CFF)
    color_end: Mapped[int] = mapped_column(BigInteger, default=0xFF3843A8)
    image_url: Mapped[str | None] = mapped_column(String(500))
    front_image_url: Mapped[str | None] = mapped_column(String(500))
    back_image_url: Mapped[str | None] = mapped_column(String(500))
    is_published: Mapped[bool] = mapped_column(Boolean, default=True, index=True)


class CatalogEvent(Base, TimestampMixin):
    __tablename__ = "catalog_events"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(180), index=True)
    name_en: Mapped[str] = mapped_column(String(180), default="")
    name_ko: Mapped[str] = mapped_column(String(180), default="")
    name_translated: Mapped[str] = mapped_column(String(180), default="")
    artist_name: Mapped[str] = mapped_column(String(180))
    group_id: Mapped[str | None] = mapped_column(ForeignKey("groups.id"), index=True)
    event_type: Mapped[str] = mapped_column(String(80), index=True)
    start_date: Mapped[str] = mapped_column(String(20), index=True)
    region: Mapped[str] = mapped_column(String(80), index=True)
    city: Mapped[str] = mapped_column(String(100), default="")
    platform: Mapped[str] = mapped_column(String(120), default="")
    venue: Mapped[str] = mapped_column(String(180), default="")
    parent_event_id: Mapped[str | None] = mapped_column(ForeignKey("catalog_events.id"), index=True)
    is_online: Mapped[bool] = mapped_column(Boolean, default=False)
    description: Mapped[str] = mapped_column(Text, default="")
    color_start: Mapped[int] = mapped_column(BigInteger, default=0xFF8B7CFF)
    color_end: Mapped[int] = mapped_column(BigInteger, default=0xFF3843A8)
    image_url: Mapped[str | None] = mapped_column(String(500))
    is_published: Mapped[bool] = mapped_column(Boolean, default=True, index=True)


class CatalogMerchandise(Base, TimestampMixin):
    __tablename__ = "catalog_merchandise"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(180), index=True)
    name_en: Mapped[str] = mapped_column(String(180), default="")
    name_ko: Mapped[str] = mapped_column(String(180), default="")
    name_translated: Mapped[str] = mapped_column(String(180), default="")
    artist_name: Mapped[str] = mapped_column(String(180))
    group_id: Mapped[str | None] = mapped_column(ForeignKey("groups.id"), index=True)
    type: Mapped[str] = mapped_column(String(80), index=True)
    source: Mapped[str] = mapped_column(String(180), default="")
    release_date: Mapped[str] = mapped_column(String(20), index=True)
    region: Mapped[str] = mapped_column(String(80), index=True)
    description: Mapped[str] = mapped_column(Text, default="")
    color_start: Mapped[int] = mapped_column(BigInteger, default=0xFF8B7CFF)
    color_end: Mapped[int] = mapped_column(BigInteger, default=0xFF3843A8)
    image_url: Mapped[str | None] = mapped_column(String(500))
    is_published: Mapped[bool] = mapped_column(Boolean, default=True, index=True)


class UserIdol(Base, TimestampMixin):
    __tablename__ = "user_idols"
    __table_args__ = (UniqueConstraint("user_id", "idol_id", "relation_type"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("ui"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    idol_id: Mapped[str] = mapped_column(ForeignKey("idols.id"), index=True)
    relation_type: Mapped[str] = mapped_column(String(30), default="favorite")
    priority: Mapped[int] = mapped_column(Integer, default=0)


class UserCollectionItem(Base, TimestampMixin):
    __tablename__ = "user_collection_items"
    __table_args__ = (UniqueConstraint("user_id", "card_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("owned"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    card_id: Mapped[str] = mapped_column(ForeignKey("cards.id"), index=True)
    quantity: Mapped[int] = mapped_column(Integer, default=1)


class UserWishlistItem(Base, TimestampMixin):
    __tablename__ = "user_wishlist_items"
    __table_args__ = (UniqueConstraint("user_id", "card_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("wish"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    card_id: Mapped[str] = mapped_column(ForeignKey("cards.id"), index=True)


class UserFollow(Base, TimestampMixin):
    __tablename__ = "user_follows"
    __table_args__ = (UniqueConstraint("follower_id", "following_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("follow"))
    follower_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    following_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )


class CardAlbum(Base, TimestampMixin):
    __tablename__ = "card_albums"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("album"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(100))
    color_start: Mapped[int] = mapped_column(BigInteger, default=0xFF8176CA)
    color_end: Mapped[int] = mapped_column(BigInteger, default=0xFF272B53)
    is_public: Mapped[bool] = mapped_column(Boolean, default=True)
    description: Mapped[str] = mapped_column(String(200), default="")
    display_type: Mapped[str] = mapped_column(String(10), default="SINGLE")
    visual_style: Mapped[str] = mapped_column(String(12), default="REALISTIC")
    # PUBLISHED preserves legacy card books. New albums explicitly start as DRAFT.
    status: Mapped[str] = mapped_column(String(12), default="PUBLISHED", index=True)
    revision: Mapped[int] = mapped_column(Integer, default=1)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    cover_config: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    card_view_config: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    published_snapshot: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    is_moderated: Mapped[bool] = mapped_column(Boolean, default=False)


class AlbumCard(Base, TimestampMixin):
    __tablename__ = "album_cards"
    __table_args__ = (UniqueConstraint("album_id", "card_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("ac"))
    album_id: Mapped[str] = mapped_column(
        ForeignKey("card_albums.id", ondelete="CASCADE"), index=True
    )
    card_id: Mapped[str] = mapped_column(ForeignKey("cards.id"), index=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)


class ProfilePhoto(Base, TimestampMixin):
    __tablename__ = "profile_photos"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("photo"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    image_url: Mapped[str] = mapped_column(String(500))
    is_public: Mapped[bool] = mapped_column(Boolean, default=True)


class DailyCardDraw(Base, TimestampMixin):
    __tablename__ = "daily_card_draws"
    __table_args__ = (
        UniqueConstraint("user_id", "draw_date", "draw_index"),
        UniqueConstraint("user_id", "request_id"),
    )
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("draw"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    card_id: Mapped[str] = mapped_column(ForeignKey("cards.id"), index=True)
    draw_date: Mapped[date] = mapped_column(Date, index=True)
    draw_index: Mapped[int] = mapped_column(Integer)
    request_id: Mapped[str] = mapped_column(String(100))


class SocialPost(Base, TimestampMixin):
    __tablename__ = "social_posts"
    __table_args__ = (UniqueConstraint("platform", "original_post_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("feed"))
    platform: Mapped[str] = mapped_column(String(30), index=True)
    original_post_id: Mapped[str] = mapped_column(String(160))
    author_type: Mapped[str] = mapped_column(String(20), default="idol")
    idol_id: Mapped[str | None] = mapped_column(ForeignKey("idols.id"), index=True)
    group_id: Mapped[str | None] = mapped_column(ForeignKey("groups.id"), index=True)
    posted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    content: Mapped[str] = mapped_column(Text, default="")
    media: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    original_url: Mapped[str] = mapped_column(String(800))
    deep_link_url: Mapped[str | None] = mapped_column(String(800))
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    relation: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    is_available: Mapped[bool] = mapped_column(Boolean, default=True)
    base_like_count: Mapped[int] = mapped_column(Integer, default=0)
    base_comment_count: Mapped[int] = mapped_column(Integer, default=0)
    share_count: Mapped[int] = mapped_column(Integer, default=0)


class SocialPostView(Base, TimestampMixin):
    __tablename__ = "social_post_views"
    __table_args__ = (UniqueConstraint("user_id", "post_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("view"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    post_id: Mapped[str] = mapped_column(
        ForeignKey("social_posts.id", ondelete="CASCADE"), index=True
    )


class SocialPostLike(Base, TimestampMixin):
    __tablename__ = "social_post_likes"
    __table_args__ = (UniqueConstraint("user_id", "post_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("plike"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    post_id: Mapped[str] = mapped_column(
        ForeignKey("social_posts.id", ondelete="CASCADE"), index=True
    )


class Comment(Base, TimestampMixin):
    __tablename__ = "comments"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("comment"))
    post_id: Mapped[str] = mapped_column(
        ForeignKey("social_posts.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    parent_id: Mapped[str | None] = mapped_column(
        ForeignKey("comments.id", ondelete="CASCADE"), index=True
    )
    reply_to_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    content: Mapped[str] = mapped_column(Text)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)


class CommentLike(Base, TimestampMixin):
    __tablename__ = "comment_likes"
    __table_args__ = (UniqueConstraint("user_id", "comment_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("clike"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    comment_id: Mapped[str] = mapped_column(
        ForeignKey("comments.id", ondelete="CASCADE"), index=True
    )


class Report(Base, TimestampMixin):
    __tablename__ = "reports"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("report"))
    reporter_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    target_type: Mapped[str] = mapped_column(String(40))
    target_id: Mapped[str] = mapped_column(String(64), index=True)
    reason: Mapped[str] = mapped_column(String(200), default="user_report")
    status: Mapped[str] = mapped_column(String(30), default="pending")


class ScanSession(Base, TimestampMixin):
    __tablename__ = "scan_sessions"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("scan"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    original_image_url: Mapped[str] = mapped_column(String(500))
    status: Mapped[str] = mapped_column(String(30), default="completed")


class DetectedCard(Base, TimestampMixin):
    __tablename__ = "detected_cards"
    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: new_id("detected")
    )
    scan_session_id: Mapped[str] = mapped_column(
        ForeignKey("scan_sessions.id", ondelete="CASCADE"), index=True
    )
    crop_image_url: Mapped[str | None] = mapped_column(String(500))
    crop_region: Mapped[dict[str, float]] = mapped_column(JSON)
    recognition_status: Mapped[str] = mapped_column(String(30))
    user_confirmed_card_id: Mapped[str | None] = mapped_column(ForeignKey("cards.id"))
    owned_added_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class ScanCandidate(Base, TimestampMixin):
    __tablename__ = "scan_candidates"
    __table_args__ = (UniqueConstraint("detected_card_id", "card_id"),)
    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: new_id("candidate")
    )
    detected_card_id: Mapped[str] = mapped_column(
        ForeignKey("detected_cards.id", ondelete="CASCADE"), index=True
    )
    card_id: Mapped[str] = mapped_column(ForeignKey("cards.id"), index=True)
    similarity: Mapped[float] = mapped_column(Float)
    feature_scores: Mapped[dict[str, float]] = mapped_column(JSON, default=dict)
    rank: Mapped[int] = mapped_column(Integer)


class ScanFeedback(Base, TimestampMixin):
    __tablename__ = "scan_feedback"
    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: new_id("feedback")
    )
    scan_session_id: Mapped[str] = mapped_column(ForeignKey("scan_sessions.id"), index=True)
    detected_card_id: Mapped[str] = mapped_column(ForeignKey("detected_cards.id"), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    group_id: Mapped[str | None] = mapped_column(ForeignKey("groups.id"))
    idol_id: Mapped[str | None] = mapped_column(ForeignKey("idols.id"))
    source: Mapped[str | None] = mapped_column(String(100))
    notes: Mapped[str | None] = mapped_column(Text)
    payload: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(30), default="pending")


class NotificationSetting(Base, TimestampMixin):
    __tablename__ = "notification_settings"
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    idol_feed_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    primary_idol_first: Mapped[bool] = mapped_column(Boolean, default=True)
    push_enabled: Mapped[bool] = mapped_column(Boolean, default=False)


class OperationLog(Base):
    __tablename__ = "operation_logs"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("op"))
    actor_id: Mapped[str] = mapped_column(String(64), index=True)
    action: Mapped[str] = mapped_column(String(100), index=True)
    target_type: Mapped[str] = mapped_column(String(60))
    target_id: Mapped[str] = mapped_column(String(64), index=True)
    before: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    after: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


# Import reserved Phase 2/3 models so SQLAlchemy metadata and Alembic discover
# them without coupling current Phase 1 modules to future domains.
from app import admin_models as admin_models  # noqa: E402,F401
from app import album_models as album_models  # noqa: E402,F401
from app import future_models as future_models  # noqa: E402,F401
