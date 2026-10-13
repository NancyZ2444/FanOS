from datetime import datetime

from pydantic import BaseModel, Field


class CommentCreate(BaseModel):
    content: str = Field(min_length=1, max_length=1000)


class ReplyCreate(CommentCreate):
    reply_to_user_id: str | None = None


class ReportCreate(BaseModel):
    reason: str = Field(default="user_report", max_length=200)


class WorkerPost(BaseModel):
    platform: str
    original_post_id: str
    author_type: str = "idol"
    idol_id: str | None = None
    group_id: str | None = None
    post_time: datetime
    content: str = ""
    media: list[dict] = []
    original_url: str
    deep_link_url: str | None = None
    fetch_time: datetime
    relation: dict | None = None
    is_available: bool = True


class WorkerPostBatch(BaseModel):
    items: list[WorkerPost] = Field(max_length=500)
