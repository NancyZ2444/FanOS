from typing import Any

from sqlalchemy import JSON, Boolean, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models import TimestampMixin, new_id


class Feedback(Base, TimestampMixin):
    __tablename__ = "catalog_user_feedback"
    __table_args__ = (UniqueConstraint("user_id", "request_key"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("fb"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    request_key: Mapped[str] = mapped_column(String(100))
    kind: Mapped[str] = mapped_column(String(20), index=True)
    entity_type: Mapped[str] = mapped_column(String(30), default="cards")
    entity_id: Mapped[str] = mapped_column(String(64), default="", index=True)
    status: Mapped[str] = mapped_column(String(20), default="PENDING", index=True)
    result: Mapped[str] = mapped_column(String(20), default="PENDING", index=True)
    revision: Mapped[int] = mapped_column(Integer, default=1)
    public_note: Mapped[str] = mapped_column(Text, default="")
    internal_note: Mapped[str] = mapped_column(Text, default="")
    handler_id: Mapped[str | None] = mapped_column(String(64), index=True)
    data: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    review: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    history: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    action_keys: Mapped[list[str]] = mapped_column(JSON, default=list)


class FeedbackImage(Base, TimestampMixin):
    __tablename__ = "catalog_feedback_images"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("fbi"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    image_url: Mapped[str] = mapped_column(String(500))


class CardContribution(Base, TimestampMixin):
    __tablename__ = "catalog_card_contributions"
    __table_args__ = (UniqueConstraint("feedback_id", "image_version_id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("credit"))
    card_id: Mapped[str] = mapped_column(ForeignKey("cards.id"), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    feedback_id: Mapped[str] = mapped_column(ForeignKey("catalog_user_feedback.id"), index=True)
    image_version_id: Mapped[str] = mapped_column(ForeignKey("card_image_versions.id"))


class FeedbackNotice(Base, TimestampMixin):
    __tablename__ = "catalog_feedback_notices"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    data: Mapped[dict[str, Any]] = mapped_column(JSON)
    delivered: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    error: Mapped[str] = mapped_column(Text, default="")
