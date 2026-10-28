from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Background(StrictModel):
    type: Literal["SOLID", "GRADIENT", "IMAGE"] = "SOLID"
    colors: list[str] = Field(default_factory=lambda: ["#E8EBE3"], min_length=1, max_length=4)
    angle: float = Field(default=45, ge=-360, le=360)

    image_url: str | None = Field(default=None, max_length=1000)
    resource_id: str | None = Field(default=None, max_length=64)
    resource_snapshot: dict | None = None

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
    stroke_width: float = Field(default=3, ge=1, le=20)
    opacity: float = Field(default=1, ge=0.1, le=1)


class Element(StrictModel):
    id: str = Field(min_length=1, max_length=64)
    type: Literal["TEXT", "EMOJI", "STICKER", "CARD", "STROKE"]
    points: list[tuple[float, float]] = Field(default_factory=list, max_length=512)
    content: str = Field(default="", max_length=500)
    x: float = Field(default=0.1, ge=-2, le=2)
    y: float = Field(default=0.1, ge=-2, le=2)
    width: float = Field(default=0.4, gt=0, le=4)
    height: float = Field(default=0.15, gt=0, le=4)
    rotation: float = Field(default=0, ge=-3600, le=3600)
    z_index: int = Field(default=0, ge=0, le=10000)
    style: ElementStyle = Field(default_factory=ElementStyle)
    resource_snapshot: dict | None = None

    @model_validator(mode="after")
    def valid_stroke(self):
        if self.type == "STROKE" and len(self.points) < 2:
            raise ValueError("画笔轨迹至少包含两个点")
        if any(not (0 <= x <= 1 and 0 <= y <= 1) for x, y in self.points):
            raise ValueError("画笔坐标须在画布范围内")
        return self


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
    default_mode: Literal["BOOK", "CARDS"] = "BOOK"
    cover_style: Literal["AUTO", "STACK_V1", "CUSTOM"] = "AUTO"
    name_display_mode: Literal["remark", "official", "combined"] = "remark"
    display_fields: list[
        Literal["idol", "group", "source", "type", "version", "release", "region", "size"]
    ] = Field(default_factory=lambda: ["idol", "group", "source"], max_length=8)


class AlbumCreate(StrictModel):
    work_mode: Literal["BOOK", "CARDS"]
    request_id: str | None = Field(default=None, min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=50)
    description: str = Field(default="", max_length=200)
    display_type: Literal["SINGLE", "DOUBLE"] | None = None
    visual_style: Literal["REALISTIC", "MINIMAL"] | None = None

    @model_validator(mode="after")
    def mode_fields(self):
        if self.work_mode == "CARDS" and (self.display_type or self.visual_style):
            raise ValueError("卡片作品不接受相册展示设置")
        return self


class Revision(StrictModel):
    revision: int = Field(ge=1)


class AlbumPatch(Revision):
    work_mode: Literal["BOOK", "CARDS"] | None = None
    card_instances: list[Slot] | None = Field(default=None, max_length=450)
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
    normal_cards: int = Field(default=15, ge=1, le=450)
    pro_cards: int = Field(default=15, ge=1, le=450)
    normal_albums: int = Field(default=10, ge=1, le=100)
    pro_albums: int = Field(default=30, ge=1, le=100)
    normal_pages: int = Field(default=10, ge=1, le=50)
    pro_pages: int = Field(default=20, ge=1, le=50)
    max_card_per_page: int = Field(default=9, ge=1, le=9)
    normal_color_daily: int = Field(default=3, ge=0, le=10000)
    normal_color_monthly: int = Field(default=20, ge=0, le=100000)
    pro_color_daily: int = Field(default=30, ge=0, le=10000)
    pro_color_monthly: int = Field(default=300, ge=0, le=100000)
    blocked_terms: list[str] = Field(default_factory=list, max_length=200)


class EntitlementPatch(StrictModel):
    plan: Literal["NORMAL", "PRO"]
    expires_at: str | None = None


class ResourcePatch(StrictModel):
    id: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    name: str = Field(min_length=1, max_length=80)
    kind: Literal["SHELF", "STICKER", "BACKGROUND", "COLOR"]
    status: Literal["DRAFT", "PUBLISHED", "OFFLINE"] = "PUBLISHED"
    scene: Literal["SHELF", "ALBUM_COVER", "ALBUM_PAGE", "CARD_BACKGROUND"]
    membership: Literal["ALL", "PRO"] = "ALL"
    locked_preview: bool = True
    sort_order: int = 0
    config: dict = Field(default_factory=dict)

    @model_validator(mode="after")
    def valid_config(self):
        import re

        self.name = self.name.strip()
        if not self.name:
            raise ValueError("请填写素材名称")
        if (self.kind == "SHELF") != (self.scene == "SHELF"):
            raise ValueError("书架主题必须使用独立书架场景")
        if self.kind == "STICKER" and self.scene not in {"ALBUM_COVER", "ALBUM_PAGE"}:
            raise ValueError("该场景不支持贴纸")
        if self.kind == "STICKER" and self.scene == "ALBUM_PAGE" and self.status == "PUBLISHED":
            raise ValueError("内页贴纸暂未开放，不能上架")
        if self.kind == "SHELF" and len(self.id) > 40:
            raise ValueError("书架素材 ID 不能超过 40 个字符")
        if self.kind in {"BACKGROUND", "COLOR"}:
            parsed = Background.model_validate(self.config)
            if parsed.resource_id or parsed.resource_snapshot:
                raise ValueError("素材配置不能引用其他素材")
            if self.kind == "COLOR" and parsed.type == "IMAGE":
                raise ValueError("颜色素材不支持图片")
            if parsed.type == "IMAGE" and not parsed.image_url:
                raise ValueError("请选择背景图片")
            self.config = parsed.model_dump(exclude_none=True)
        elif self.kind == "STICKER":
            symbol = self.config.get("symbol")
            image = self.config.get("image_url")
            if not (
                set(self.config) == {"symbol"}
                and isinstance(symbol, str)
                and 1 <= len(symbol) <= 24
            ) and not (set(self.config) == {"image_url"} and isinstance(image, str) and image):
                raise ValueError("贴纸须提供符号或已上传图片")
        else:
            colors = self.config.get("colors", [])
            ledge = self.config.get("ledge", "")
            if (
                set(self.config) - {"colors", "ledge", "image_url"}
                or not 2 <= len(colors) <= 4
                or any(
                    not isinstance(c, str) or not re.fullmatch(r"#[0-9A-Fa-f]{6}", c)
                    for c in [*colors, ledge]
                )
            ):
                raise ValueError("书架须提供 2–4 个 #RRGGBB 颜色和层板颜色")
        return self


class CardAssetsRequest(StrictModel):
    card_ids: list[str] = Field(max_length=451)


class AlbumReport(StrictModel):
    reason: str = Field(min_length=1, max_length=200)


class ModerationPatch(StrictModel):
    offline: bool | None = None
    status: Literal["NORMAL", "RESTRICTED", "OFFLINE"] | None = None
    reason_code: Literal[
        "PORNOGRAPHY",
        "ILLEGAL",
        "PRIVACY",
        "COPYRIGHT",
        "MALICIOUS",
        "SPAM",
        "TEXT",
        "IMAGE",
        "OTHER",
    ] = "OTHER"
    reason: str = Field(min_length=1, max_length=200)
    note: str = Field(default="", max_length=1000)
    resolve_report_ids: list[str] = Field(default_factory=list, max_length=200)
    review_id: str | None = None

    @model_validator(mode="after")
    def valid_action(self):
        self.reason = self.reason.strip()
        if not self.reason or (self.status is None and self.offline is None):
            raise ValueError("请选择处理动作并填写原因")
        if (
            self.status is not None
            and self.offline is not None
            and self.offline != (self.status != "NORMAL")
        ):
            raise ValueError("处理状态不一致")
        return self


class ReviewReject(StrictModel):
    review_id: str
    reason: str = Field(min_length=1, max_length=500)
