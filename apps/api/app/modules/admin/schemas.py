from pydantic import BaseModel, Field


class CardUpsert(BaseModel):
    id: str
    title: str
    title_en: str = ""
    title_ko: str = ""
    title_translated: str = ""
    idol_id: str
    group_id: str
    source: str
    card_type: str
    version: str
    release_date: str
    region: str
    color_start: int = 0xFF8B7CFF
    color_end: int = 0xFF3843A8
    image_url: str | None = None


class UserStatusPatch(BaseModel):
    is_active: bool


class FeedbackStatusPatch(BaseModel):
    status: str = Field(pattern="^(pending|reviewing|resolved|rejected)$")
