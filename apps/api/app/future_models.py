"""Reserved Phase 2/3 persistence boundaries.

These tables are intentionally not wired into Phase 1 routes. They reserve
separate Community, delivery, and integration-event models so external Idol
feed comments never become the storage model for user-generated community
content. Realtime chat messages remain outside the business API database.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _id(prefix: str) -> str:
    return f"{prefix}_{uuid4().hex}"


def _utcnow() -> datetime:
    return datetime.now(UTC)


class FutureTimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )


class CommunityPost(Base, FutureTimestampMixin):
    __tablename__ = "community_posts"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: _id("cpost"))
    author_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    subject_type: Mapped[str | None] = mapped_column(String(30), index=True)
    subject_id: Mapped[str | None] = mapped_column(String(64), index=True)
    content: Mapped[str] = mapped_column(Text, default="")
    visibility: Mapped[str] = mapped_column(String(20), default="public", index=True)
    status: Mapped[str] = mapped_column(String(30), default="published", index=True)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    view_count: Mapped[int] = mapped_column(Integer, default=0)
    reaction_count: Mapped[int] = mapped_column(Integer, default=0)
    comment_count: Mapped[int] = mapped_column(Integer, default=0)


class CommunityPostMedia(Base, FutureTimestampMixin):
    __tablename__ = "community_post_media"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: _id("cmedia"))
    post_id: Mapped[str] = mapped_column(
        ForeignKey("community_posts.id", ondelete="CASCADE"), index=True
    )
    media_type: Mapped[str] = mapped_column(String(20))
    url: Mapped[str] = mapped_column(String(800))
    cover_url: Mapped[str | None] = mapped_column(String(800))
    width: Mapped[int | None] = mapped_column(Integer)
    height: Mapped[int | None] = mapped_column(Integer)
    duration_ms: Mapped[int | None] = mapped_column(Integer)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    moderation_status: Mapped[str] = mapped_column(String(30), default="pending", index=True)


class CommunityComment(Base, FutureTimestampMixin):
    __tablename__ = "community_comments"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: _id("ccomment"))
    post_id: Mapped[str] = mapped_column(
        ForeignKey("community_posts.id", ondelete="CASCADE"), index=True
    )
    author_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    parent_id: Mapped[str | None] = mapped_column(
        ForeignKey("community_comments.id", ondelete="CASCADE"), index=True
    )
    reply_to_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    content: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(30), default="published", index=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class CommunityReaction(Base, FutureTimestampMixin):
    __tablename__ = "community_reactions"
    __table_args__ = (UniqueConstraint("user_id", "target_type", "target_id", "reaction_type"),)

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: _id("creact"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    target_type: Mapped[str] = mapped_column(String(20), index=True)
    target_id: Mapped[str] = mapped_column(String(64), index=True)
    reaction_type: Mapped[str] = mapped_column(String(20), default="like")


class CommunityBookmark(Base, FutureTimestampMixin):
    __tablename__ = "community_bookmarks"
    __table_args__ = (UniqueConstraint("user_id", "post_id"),)

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: _id("cmark"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    post_id: Mapped[str] = mapped_column(
        ForeignKey("community_posts.id", ondelete="CASCADE"), index=True
    )


class CommunityModerationCase(Base, FutureTimestampMixin):
    __tablename__ = "community_moderation_cases"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: _id("cmod"))
    reporter_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    target_type: Mapped[str] = mapped_column(String(30), index=True)
    target_id: Mapped[str] = mapped_column(String(64), index=True)
    reason: Mapped[str] = mapped_column(String(100))
    details: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[str] = mapped_column(String(30), default="pending", index=True)
    reviewer_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    resolution: Mapped[str | None] = mapped_column(Text)


class UserBlock(Base, FutureTimestampMixin):
    __tablename__ = "user_blocks"
    __table_args__ = (UniqueConstraint("blocker_id", "blocked_id"),)

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: _id("block"))
    blocker_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    blocked_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)


class OutboxEvent(Base):
    __tablename__ = "outbox_events"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: _id("event"))
    event_type: Mapped[str] = mapped_column(String(120), index=True)
    event_version: Mapped[int] = mapped_column(Integer, default=1)
    aggregate_type: Mapped[str] = mapped_column(String(60), index=True)
    aggregate_id: Mapped[str] = mapped_column(String(64), index=True)
    payload: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, index=True
    )
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    publish_attempts: Mapped[int] = mapped_column(Integer, default=0)
    last_error: Mapped[str | None] = mapped_column(Text)


class NotificationInboxItem(Base, FutureTimestampMixin):
    __tablename__ = "notifications"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: _id("notice"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    category: Mapped[str] = mapped_column(String(40), index=True)
    source_type: Mapped[str | None] = mapped_column(String(40), index=True)
    source_id: Mapped[str | None] = mapped_column(String(64), index=True)
    title: Mapped[str] = mapped_column(String(160))
    body: Mapped[str] = mapped_column(String(500), default="")
    payload: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)


class DeviceToken(Base, FutureTimestampMixin):
    __tablename__ = "device_tokens"
    __table_args__ = (UniqueConstraint("platform", "token"),)

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: _id("device"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    platform: Mapped[str] = mapped_column(String(20), index=True)
    token: Mapped[str] = mapped_column(String(500))
    app_version: Mapped[str | None] = mapped_column(String(40))
    locale: Mapped[str | None] = mapped_column(String(20))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
