"""Transport-neutral commands for the future user community domain."""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel, Field, model_validator


class CommunitySubjectType(StrEnum):
    idol = "idol"
    group = "group"
    custom = "custom"


class CommunityMediaType(StrEnum):
    image = "image"
    video = "video"


class CommunityTargetType(StrEnum):
    post = "post"
    comment = "comment"


class CommunityMediaCreate(BaseModel):
    media_type: CommunityMediaType
    url: str = Field(min_length=1, max_length=800)
    cover_url: str | None = Field(default=None, max_length=800)
    width: int | None = Field(default=None, ge=1)
    height: int | None = Field(default=None, ge=1)
    duration_ms: int | None = Field(default=None, ge=0)


class CommunityPostCreate(BaseModel):
    content: str = Field(default="", max_length=5000)
    subject_type: CommunitySubjectType | None = None
    subject_id: str | None = Field(default=None, max_length=64)
    media: list[CommunityMediaCreate] = Field(default_factory=list, max_length=9)

    @model_validator(mode="after")
    def validate_subject_and_content(self) -> CommunityPostCreate:
        if bool(self.subject_type) != bool(self.subject_id):
            raise ValueError("subject_type and subject_id must be provided together")
        if not self.content.strip() and not self.media:
            raise ValueError("a post needs text or media")
        return self


class CommunityCommentCreate(BaseModel):
    content: str = Field(min_length=1, max_length=1000)
    parent_id: str | None = Field(default=None, max_length=64)
    reply_to_user_id: str | None = Field(default=None, max_length=64)


class CommunityReactionCommand(BaseModel):
    target_type: CommunityTargetType
    target_id: str = Field(min_length=1, max_length=64)
    reaction_type: str = Field(default="like", min_length=1, max_length=20)
