from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class PrivacyPatch(BaseModel):
    collection_visible: bool | None = None
    likes_visible: bool | None = None
    albums_visible: bool | None = None
    photos_visible: bool | None = None
    following_list_visible: bool | None = None
    followers_list_visible: bool | None = None
    favorites_visible: bool | None = None
    discoverable: bool | None = None


class ProfilePatch(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=20)
    bio: str | None = Field(default=None, max_length=120)
    avatar_url: str | None = None
    weibo_visible: bool | None = None
    privacy: PrivacyPatch | None = None


class FavoriteUpdate(BaseModel):
    idol_ids: list[str] = Field(max_length=20)
    primary_idol_id: str | None = None


class NameDisplayPatch(BaseModel):
    mode: Literal["official", "remark", "combined"]


class NameRemarkPatch(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    remark: str = Field(default="", max_length=40)
