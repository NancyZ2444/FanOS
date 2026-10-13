"""Versioned commands/events shared with a future realtime service."""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, Field, model_validator


class ChatRoomType(StrEnum):
    group = "group"
    direct = "direct"


class ChatSubjectType(StrEnum):
    group = "group"
    idol = "idol"
    custom = "custom"


class ChatMessageType(StrEnum):
    text = "text"
    image = "image"
    sticker = "sticker"
    idol_card = "idol_card"
    post_share = "post_share"
    collection_share = "collection_share"
    system = "system"


class EntityReference(BaseModel):
    type: str = Field(min_length=1, max_length=40)
    target_id: str = Field(min_length=1, max_length=64)
    version: int = Field(default=1, ge=1)


class SendMessageCommand(BaseModel):
    room_id: str = Field(min_length=1, max_length=64)
    client_message_id: str = Field(min_length=1, max_length=64)
    message_type: ChatMessageType
    content: str | None = Field(default=None, max_length=5000)
    target: EntityReference | None = None
    reply_message_id: str | None = Field(default=None, max_length=64)

    @model_validator(mode="after")
    def validate_payload(self) -> SendMessageCommand:
        if self.message_type == ChatMessageType.text and not (self.content or "").strip():
            raise ValueError("text messages require content")
        if (
            self.message_type
            in {
                ChatMessageType.idol_card,
                ChatMessageType.post_share,
                ChatMessageType.collection_share,
            }
            and self.target is None
        ):
            raise ValueError("share messages require a target reference")
        return self


class ChatMessageEvent(BaseModel):
    schema_version: int = Field(default=1, ge=1)
    message_id: str
    room_id: str
    room_sequence: int = Field(ge=1)
    sender_id: str
    message_type: ChatMessageType
    content: str | None = None
    target: EntityReference | None = None
    reply_message_id: str | None = None
    sent_at: datetime


class ChatReadCommand(BaseModel):
    room_id: str = Field(min_length=1, max_length=64)
    last_read_sequence: int = Field(ge=0)
