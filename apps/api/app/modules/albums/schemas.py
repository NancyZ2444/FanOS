from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Background(StrictModel):
    type: Literal["SOLID", "GRADIENT"] = "GRADIENT"
    colors: list[str] = Field(
        default_factory=lambda: ["#EDE8FF", "#F9EDF2"], min_length=1, max_length=4
    )
    angle: float = Field(default=45, ge=-360, le=360)

    @model_validator(mode="after")
    def valid_colors(self):
        import re

        if any(not re.fullmatch(r"#[0-9A-Fa-f]{6}", color) for color in self.colors):
            raise ValueError("颜色必须是 #RRGGBB")
        if self.type == "GRADIENT" and len(self.colors) < 2:
            raise ValueError("渐变背景至少需要两个颜色")
        return self


class ElementStyle(StrictModel):
    color: str = Field(default="#342A56", pattern=r"^#[0-9A-Fa-f]{6}$")
    font_size: float = Field(default=20, ge=8, le=96)
    font_family: Literal["system", "serif", "monospace"] = "system"
    bold: bool = False


class Element(StrictModel):
    id: str = Field(min_length=1, max_length=64)
    type: Literal["TEXT", "EMOJI", "STICKER", "CARD"]
    content: str = Field(default="", max_length=500)
    x: float = Field(default=0.1, ge=-2, le=2)
    y: float = Field(default=0.1, ge=-2, le=2)
    width: float = Field(default=0.4, gt=0, le=4)
    height: float = Field(default=0.15, gt=0, le=4)
    rotation: float = Field(default=0, ge=-3600, le=3600)
    z_index: int = Field(default=0, ge=0, le=10000)
    style: ElementStyle = Field(default_factory=ElementStyle)


class CanvasConfig(StrictModel):
    background: Background = Field(default_factory=Background)
    elements: list[Element] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def unique_elements(self):
        if len({e.id for e in self.elements}) != len(self.elements):
            raise ValueError("元素 ID 不能重复")
        return self


class Slot(StrictModel):
    id: str = Field(min_length=1, max_length=64)
    card_id: str | None = Field(default=None, max_length=64)


class Page(StrictModel):
    id: str = Field(min_length=1, max_length=64)
    grid_count: int = Field(default=9, ge=1, le=9)
    config: CanvasConfig = Field(default_factory=CanvasConfig)
    slots: list[Slot] = Field(min_length=1, max_length=9)

    @model_validator(mode="after")
    def slots_fit(self):
        if len(self.slots) != self.grid_count:
            raise ValueError("卡位数量必须与布局一致")
        if any(e.type == "CARD" for e in self.config.elements):
            raise ValueError("内页小卡必须放在固定卡位中")
        return self


class CardView(StrictModel):
    featured_slot_id: str | None = Field(default=None, max_length=64)
    card_order: list[str] = Field(default_factory=list, max_length=450)
    order_customized: bool = False
    background: Background = Field(default_factory=Background)
    animation_style: Literal["STACK"] = "STACK"


class AlbumCreate(StrictModel):
    name: str = Field(min_length=1, max_length=50)
    description: str = Field(default="", max_length=200)
    display_type: Literal["SINGLE", "DOUBLE"] = "SINGLE"
    visual_style: Literal["REALISTIC", "MINIMAL"] = "REALISTIC"


class Revision(StrictModel):
    revision: int = Field(ge=1)


class AlbumPatch(Revision):
    name: str | None = Field(default=None, min_length=1, max_length=50)
    description: str | None = Field(default=None, max_length=200)
    display_type: Literal["SINGLE", "DOUBLE"] | None = None
    visual_style: Literal["REALISTIC", "MINIMAL"] | None = None
    visibility: Literal["PUBLIC", "PRIVATE"] | None = None
    cover: CanvasConfig | None = None
    card_view: CardView | None = None
    pages: list[Page] | None = Field(default=None, max_length=50)
    confirm_removal: bool = False
    confirm_duplicates: bool = False


class PageCreate(Revision):
    grid_count: int = Field(default=9, ge=1, le=9)
    after_page_id: str | None = None


class PagePatch(Revision):
    grid_count: int | None = Field(default=None, ge=1, le=9)
    config: CanvasConfig | None = None
    confirm_removal: bool = False


class SlotsPatch(Revision):
    slots: list[Slot] = Field(max_length=9)
    confirm_duplicates: bool = False


class OrderPatch(Revision):
    page_ids: list[str] = Field(max_length=50)


class CoverPatch(Revision):
    cover: CanvasConfig


class DisplayPatch(Revision):
    display_type: Literal["SINGLE", "DOUBLE"]
    visual_style: Literal["REALISTIC", "MINIMAL"]


class CardViewPatch(Revision):
    card_view: CardView


class VisibilityPatch(Revision):
    visibility: Literal["PUBLIC", "PRIVATE"]


class PreferencesPatch(StrictModel):
    shelf_theme: str = Field(max_length=40)
    view_mode: Literal["SHELF", "LIST"]


class AlbumLimits(StrictModel):
    normal_albums: int = Field(default=10, ge=1, le=100)
    pro_albums: int = Field(default=30, ge=1, le=100)
    normal_pages: int = Field(default=10, ge=1, le=50)
    pro_pages: int = Field(default=20, ge=1, le=50)
    max_card_per_page: int = Field(default=9, ge=1, le=9)
    blocked_terms: list[str] = Field(default_factory=list, max_length=200)


class EntitlementPatch(StrictModel):
    plan: Literal["NORMAL", "PRO"]
    expires_at: str | None = None


class ResourcePatch(StrictModel):
    id: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=80)
    kind: Literal["SHELF", "STICKER", "BACKGROUND"]
    status: Literal["PUBLISHED", "OFFLINE"] = "PUBLISHED"
    sort_order: int = 0
    config: dict = Field(default_factory=dict)

    @model_validator(mode="after")
    def valid_config(self):
        import re

        if self.kind == "BACKGROUND":
            self.config = Background.model_validate(self.config).model_dump()
        elif self.kind == "STICKER":
            if (
                set(self.config) != {"symbol"}
                or not isinstance(self.config["symbol"], str)
                or not 1 <= len(self.config["symbol"]) <= 24
            ):
                raise ValueError("系统贴纸须提供 1–24 个字符的 symbol")
        else:
            colors = self.config.get("colors", [])
            ledge = self.config.get("ledge", "")
            if (
                set(self.config) != {"colors", "ledge"}
                or not isinstance(colors, list)
                or not 2 <= len(colors) <= 4
                or any(
                    not isinstance(c, str) or not re.fullmatch(r"#[0-9A-Fa-f]{6}", c)
                    for c in [*colors, ledge]
                )
            ):
                raise ValueError("书架须提供 2–4 个 #RRGGBB 颜色和 ledge 颜色")
        return self


class CardAssetsRequest(StrictModel):
    card_ids: list[str] = Field(max_length=451)


class AlbumReport(StrictModel):
    reason: str = Field(min_length=1, max_length=200)


class ModerationPatch(StrictModel):
    offline: bool
    reason: str = Field(min_length=1, max_length=200)
