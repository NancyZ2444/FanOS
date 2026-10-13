"""Suggest a card boundary, then apply the operator's confirmed corners exactly."""

import base64
import io

import cv2
import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator

from app.common.response import DomainError
from app.integrations.card_matcher.adapter import CardMatcherAdapter


class CropPoint(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)
    x: float = Field(ge=0, le=1)
    y: float = Field(ge=0, le=1)


class CardCrop(BaseModel):
    model_config = ConfigDict(extra="forbid")
    points: list[CropPoint] = Field(min_length=4, max_length=4)

    @model_validator(mode="after")
    def validate_polygon(self):
        # Image coordinates are clockwise: TL, TR, BR, BL. Reject crossed,
        # concave, reversed and degenerate selections before allocating a warp.
        p = self.points
        crosses = [
            (p[(i + 1) % 4].x - p[i].x) * (p[(i + 2) % 4].y - p[(i + 1) % 4].y)
            - (p[(i + 1) % 4].y - p[i].y) * (p[(i + 2) % 4].x - p[(i + 1) % 4].x)
            for i in range(4)
        ]
        area = sum(p[i].x * p[(i + 1) % 4].y - p[(i + 1) % 4].x * p[i].y for i in range(4)) / 2
        if min(crosses) <= 1e-8 or area < 0.0001:
            raise ValueError("Invalid crop boundary")
        return self


def parse_crop(value: str) -> CardCrop:
    try:
        return CardCrop.model_validate_json(value)
    except ValidationError as exc:
        raise DomainError(
            "INVALID_CROP", "请按顺时针调整小卡四角，裁剪区域不能交叉或过小", 422
        ) from exc


def load_image(raw: bytes) -> Image.Image:
    try:
        with Image.open(io.BytesIO(raw)) as image:
            if (
                image.format not in {"JPEG", "PNG", "WEBP"}
                or image.width * image.height > 40_000_000
            ):
                raise ValueError("Invalid image")
            image.load()
            return ImageOps.exif_transpose(image).convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise DomainError(
            "INVALID_IMAGE", "请上传有效的 JPG、PNG 或 WebP 小卡图片（不超过 4000 万像素）", 422
        ) from exc


def crop_preview(raw: bytes) -> dict:
    image = load_image(raw)
    # Detect on a bounded copy; suggestions use normalized, orientation-correct
    # coordinates and the final crop is applied to the original-resolution image.
    detection = image.copy()
    detection.thumbnail((2400, 2400))
    buffer = io.BytesIO()
    detection.save(buffer, format="PNG")
    try:
        regions = CardMatcherAdapter.detect(buffer.getvalue())
        choices = [{"points": r.corners} for r in regions if r.corners]
    except (OverflowError, cv2.error):
        choices = []  # Crowded/undetectable photo: allow manual isolation.
    preview = image.copy()
    preview.thumbnail((1200, 1200))
    buffer = io.BytesIO()
    preview.save(buffer, format="JPEG", quality=90)
    return {
        "preview_url": "data:image/jpeg;base64," + base64.b64encode(buffer.getvalue()).decode(),
        "width": image.width,
        "height": image.height,
        "regions": choices,
    }


def apply_crop(image: Image.Image, crop: CardCrop) -> Image.Image:
    points = np.float32([[p.x * (image.width - 1), p.y * (image.height - 1)] for p in crop.points])
    w = round(max(np.linalg.norm(points[1] - points[0]), np.linalg.norm(points[2] - points[3]))) + 1
    h = round(max(np.linalg.norm(points[3] - points[0]), np.linalg.norm(points[2] - points[1]))) + 1
    if min(w, h) < 8:
        raise DomainError("INVALID_CROP", "裁剪区域过小，请保留完整小卡", 422)
    scale = min(1, 5000 / max(w, h))
    w, h = max(1, round(w * scale)), max(1, round(h * scale))
    target = np.float32([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]])
    return Image.fromarray(
        cv2.warpPerspective(np.asarray(image), cv2.getPerspectiveTransform(points, target), (w, h))
    )
