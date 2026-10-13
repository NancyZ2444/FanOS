from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

SourceType = Literal[
    "OFFICIAL",
    "SOCIAL_MEDIA",
    "USER_SUBMITTED",
    "ADMIN_UPLOAD",
    "PARTNER",
    "PUBLIC_DATABASE",
    "OTHER",
]
CopyrightStatus = Literal[
    "UNKNOWN", "OFFICIAL_SOURCE", "AUTHORIZED", "FAIR_USE_REVIEW", "RESTRICTED", "REMOVED"
]
ImportKind = Literal[
    "cards",
    "groups",
    "idols",
    "albums",
    "events",
    "others",
    "groups_idols",
    "companies",
]


class SourceInfo(BaseModel):
    source_type: SourceType = "ADMIN_UPLOAD"
    source_url: str = Field(default="", max_length=800)
    source_platform: str = Field(default="", max_length=100)
    source_account: str = Field(default="", max_length=120)
    source_reference: str = Field(default="", max_length=500)
    copyright_status: CopyrightStatus = "UNKNOWN"
    copyright_note: str = Field(default="", max_length=1000)

    @field_validator("source_url")
    @classmethod
    def valid_url(cls, value: str) -> str:
        if value and not value.startswith(("https://", "http://")):
            raise ValueError("来源链接必须以 https:// 或 http:// 开头")
        return value


class CardDraft(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    title: str = Field(default="", max_length=180)
    title_en: str = Field(default="", max_length=220)
    title_ko: str = Field(default="", max_length=220)
    title_translated: str = Field(default="", max_length=220)
    group_id: str | None = Field(default=None, max_length=64)
    idol_id: str | None = None
    source_entity_type: Literal["ALBUM", "EVENT", "OTHER"] = "ALBUM"
    source_entity_id: str = ""
    card_type: str = Field(default="Regular", max_length=80)
    version: str = Field(default="", max_length=100)
    entity_version_id: str | None = None
    batch_id: str | None = None
    edition: str = Field(default="", max_length=100)
    card_number: str = Field(default="", max_length=100)
    rarity: str = "R"
    release_date: str = Field(default="", max_length=20)
    region: str = Field(default="", max_length=80)
    tags: list[str] = Field(default_factory=list, max_length=30)
    image_url: str | None = Field(default=None, max_length=500)
    back_image_url: str | None = Field(default=None, max_length=500)
    is_group_pc: bool = False
    is_double_sided: bool = False
    is_official: bool = True
    is_limited: bool = False
    is_random: bool = False
    has_ar: bool = False
    ar_type: Literal["IMAGE", "VIDEO", "3D", "ANIMATION", "WEB_AR"] = "IMAGE"
    ar_resource: str = Field(default="", max_length=800)
    ar_preview: str = Field(default="", max_length=800)
    ar_status: Literal["Draft", "Processing", "Ready", "Failed", "Offline"] = "Draft"
    source_info: SourceInfo = Field(default_factory=SourceInfo)
    front_source: SourceInfo = Field(default_factory=SourceInfo)
    back_source: SourceInfo = Field(default_factory=SourceInfo)
    expected_updated_at: str | None = None

    @field_validator("image_url", "back_image_url", "ar_resource", "ar_preview")
    @classmethod
    def safe_media(cls, value: str | None) -> str | None:
        if value and not value.startswith(("https://", "http://", "/media/")):
            raise ValueError("请输入有效的 HTTP(S) 素材地址")
        return value


class EntityDraft(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=120)
    original_name: str = Field(default="", max_length=180)
    start_date: str = Field(default="", max_length=10)
    name_en: str = Field(default="", max_length=180)
    name_ko: str = Field(default="", max_length=180)
    name_translated: str = Field(default="", max_length=180)
    group_id: str = ""
    idol_id: str | None = None
    artists: list[dict[str, str]] = Field(default_factory=list)
    versions: list[str] = Field(default_factory=list, max_length=100)
    parent_event_id: str | None = None
    album_id: str | None = None
    end_date: str = ""
    city: str = ""
    platform: str = Field(default="", max_length=120)
    venue: str = ""
    is_online: bool = False
    business_status: str = ""
    real_name: str = ""
    gender: str = ""
    fandom_name: str = ""
    official_website: str = ""
    cover_image: str = ""
    aliases: list[str] = Field(default_factory=list)
    company: str = Field(default="", max_length=120)
    company_ids: list[str] | None = Field(default=None, max_length=20)
    company_effective_date: str = Field(default="", max_length=10)
    group_code: str = Field(default="", max_length=80)
    description: str = ""
    release_date: str = Field(default="", max_length=20)
    region: str = Field(default="", max_length=80)
    type: str = Field(default="", max_length=80)
    image_url: str | None = Field(default=None, max_length=500)
    tags: list[str] = Field(default_factory=list)
    source_info: SourceInfo = Field(default_factory=SourceInfo)
    official_accounts: list[dict[str, str | bool]] = Field(default_factory=list)

    @field_validator("versions")
    @classmethod
    def validate_versions(cls, values: list[str]) -> list[str]:
        from .album_versions import version_key

        clean = [v.strip() for v in values]
        if any(not v or len(v) > 120 for v in clean):
            raise ValueError("版本名称须为 1–120 字符")
        if len({version_key(v) for v in clean}) != len(clean):
            raise ValueError("版本名称不能重复")
        return clean


class ActionRequest(BaseModel):
    action: Literal[
        "submit",
        "publish",
        "offline",
        "reject",
        "archive",
        "restore",
        "approve",
        "send",
        "test-send",
        "resolve",
        "hide",
        "delete",
        "ban",
        "unban",
        "cancel",
    ]
    reason: str = Field(default="", max_length=1000)
    confirmation: str = ""


class BatchAction(BaseModel):
    ids: list[str] = Field(min_length=1, max_length=100)
    action: Literal["submit", "publish", "offline", "archive", "restore", "delete"]


class ImportConfirm(BaseModel):
    skip_invalid: bool = False


class OpsDraft(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    content: str = Field(default="", max_length=500)
    group_id: str = ""
    idol_id: str = ""
    platform: str = "MANUAL"
    source_url: str = ""
    image_url: str = ""
    card_ids: list[str] = Field(default_factory=list)
    target_type: Literal["NONE", "CARD", "ALBUM", "GROUP", "IDOL"] = "NONE"
    target_id: str = ""
    audience: Literal["ALL", "FAVORITE_IDOL"] = "ALL"
    audience_idol_id: str = ""
    start_time: str = ""
    end_time: str = ""
    priority: int = Field(default=0, ge=0, le=100)
    weights: dict[str, int] = Field(default_factory=dict)
