"""Operational metadata kept separate from the public catalog contract."""

from __future__ import annotations

from typing import Any

from sqlalchemy import JSON, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models import TimestampMixin, new_id


class ContentMetadata(Base, TimestampMixin):
    __tablename__ = "admin_content_metadata"
    __table_args__ = (UniqueConstraint("entity_type", "entity_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("meta"))
    entity_type: Mapped[str] = mapped_column(String(40), index=True)
    entity_id: Mapped[str] = mapped_column(String(64), index=True)
    status: Mapped[str] = mapped_column(String(30), default="DRAFT", index=True)
    data: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    operator_id: Mapped[str] = mapped_column(String(64))


class CatalogCollection(Base, TimestampMixin):
    __tablename__ = "catalog_collections"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("set"))
    name: Mapped[str] = mapped_column(String(180))
    group_id: Mapped[str | None] = mapped_column(ForeignKey("groups.id"), index=True)

    entity_type: Mapped[str] = mapped_column(String(30), default="COLLECTION")
    description: Mapped[str] = mapped_column(Text, default="")
    release_date: Mapped[str] = mapped_column(String(20), default="")
    image_url: Mapped[str | None] = mapped_column(String(500))


class CardImageVersion(Base, TimestampMixin):
    __tablename__ = "card_image_versions"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("img"))
    card_id: Mapped[str] = mapped_column(ForeignKey("cards.id"), index=True)
    side: Mapped[str] = mapped_column(String(10))
    version: Mapped[int] = mapped_column(Integer)
    data: Mapped[dict[str, Any]] = mapped_column(JSON)
    operator_id: Mapped[str] = mapped_column(String(64))


class AdminImportTask(Base, TimestampMixin):
    __tablename__ = "admin_import_tasks"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("import"))
    filename: Mapped[str] = mapped_column(String(240))
    kind: Mapped[str] = mapped_column(String(30), default="cards", server_default="cards")
    status: Mapped[str] = mapped_column(String(30), default="VALIDATED")
    rows: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    errors: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    imported_count: Mapped[int] = mapped_column(Integer, default=0)
    operator_id: Mapped[str] = mapped_column(String(64))
