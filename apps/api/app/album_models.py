"""Digital album instances and display settings, independent of Owned/Wishlist."""

from datetime import datetime
from typing import Any

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models import TimestampMixin, new_id


class AlbumPage(Base, TimestampMixin):
    __tablename__ = "digital_album_pages"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    album_id: Mapped[str] = mapped_column(
        ForeignKey("card_albums.id", ondelete="CASCADE"), index=True
    )
    page_order: Mapped[int] = mapped_column(Integer)
    grid_count: Mapped[int] = mapped_column(Integer, default=9)
    page_config: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)


class AlbumSlot(Base, TimestampMixin):
    __tablename__ = "digital_album_slots"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    page_id: Mapped[str] = mapped_column(
        ForeignKey("digital_album_pages.id", ondelete="CASCADE"), index=True
    )
    slot_order: Mapped[int] = mapped_column(Integer)
    # No (album, card) uniqueness: every placement is a distinct instance.
    card_id: Mapped[str | None] = mapped_column(ForeignKey("cards.id"), index=True)


class AlbumReaction(Base, TimestampMixin):
    __tablename__ = "digital_album_reactions"
    __table_args__ = (UniqueConstraint("user_id", "album_id", "kind"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("ar"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    album_id: Mapped[str] = mapped_column(ForeignKey("card_albums.id"), index=True)
    kind: Mapped[str] = mapped_column(String(10))


class AlbumPreferences(Base, TimestampMixin):
    __tablename__ = "digital_album_preferences"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    shelf_theme: Mapped[str] = mapped_column(String(40), default="cream-white")
    view_mode: Mapped[str] = mapped_column(String(10), default="SHELF")


class AlbumFavoriteGroup(Base, TimestampMixin):
    __tablename__ = "digital_album_favorite_groups"
    __table_args__ = (UniqueConstraint("user_id", "name"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("afg"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(40))
    is_public: Mapped[bool] = mapped_column(Boolean, default=False)


class AlbumFavoritePlacement(Base):
    __tablename__ = "digital_album_favorite_placements"
    reaction_id: Mapped[str] = mapped_column(
        ForeignKey("digital_album_reactions.id", ondelete="CASCADE"), primary_key=True
    )
    group_id: Mapped[str] = mapped_column(
        ForeignKey("digital_album_favorite_groups.id", ondelete="CASCADE"), index=True
    )


class AlbumEntitlement(Base, TimestampMixin):
    __tablename__ = "digital_album_entitlements"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    plan: Mapped[str] = mapped_column(String(10), default="NORMAL")
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AlbumSettings(Base, TimestampMixin):
    __tablename__ = "digital_album_settings"
    id: Mapped[str] = mapped_column(String(40), primary_key=True, default="global")
    config: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)


class AlbumResource(Base, TimestampMixin):
    __tablename__ = "digital_album_resources"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    kind: Mapped[str] = mapped_column(String(20))
    status: Mapped[str] = mapped_column(String(12), default="PUBLISHED")
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    config: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
