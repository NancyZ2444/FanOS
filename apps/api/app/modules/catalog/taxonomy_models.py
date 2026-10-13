"""Stable Other sources and entity-scoped, flat catalog tags."""

from typing import Any

from sqlalchemy import JSON, Boolean, ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models import TimestampMixin, new_id


class CatalogOther(Base, TimestampMixin):
    __tablename__ = "catalog_others"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("other"))
    name: Mapped[str] = mapped_column(String(180), index=True)
    original_name: Mapped[str] = mapped_column(String(180), default="")
    start_date: Mapped[str] = mapped_column(String(20), default="", index=True)
    end_date: Mapped[str] = mapped_column(String(20), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    is_published: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    # First associated group; complete group/idol relationships live in ContentMetadata.artists.
    group_id: Mapped[str | None] = mapped_column(ForeignKey("groups.id"), index=True)
    legacy_data: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)


class CatalogTag(Base, TimestampMixin):
    __tablename__ = "catalog_tags"
    __table_args__ = (
        UniqueConstraint("entity_type", "normalized_name", name="uq_catalog_tag_scope_name"),
    )
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("tag"))
    entity_type: Mapped[str] = mapped_column(String(20), index=True)
    name: Mapped[str] = mapped_column(String(80))
    normalized_name: Mapped[str] = mapped_column(String(160))
    source: Mapped[str] = mapped_column(String(30), default="INTERNAL")
    status: Mapped[str] = mapped_column(String(20), default="ACTIVE", index=True)
    operator_id: Mapped[str] = mapped_column(String(64), default="legacy")
    submission_id: Mapped[str | None] = mapped_column(String(64))


class CatalogTagBinding(Base, TimestampMixin):
    __tablename__ = "catalog_tag_bindings"
    __table_args__ = (
        UniqueConstraint("entity_type", "entity_id", "tag_id", name="uq_catalog_tag_binding"),
    )
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("taglink"))
    entity_type: Mapped[str] = mapped_column(String(20), index=True)
    entity_id: Mapped[str] = mapped_column(String(64), index=True)
    tag_id: Mapped[str] = mapped_column(ForeignKey("catalog_tags.id"), index=True)
