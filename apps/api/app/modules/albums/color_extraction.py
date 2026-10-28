"""Bounded picture colour analysis; uploaded photos are never stored."""

from __future__ import annotations

import io

from fastapi import APIRouter, Depends, File, Form, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.album_models import AlbumColorExtraction
from app.common.response import DomainError, success
from app.core.config import get_settings
from app.core.database import get_db
from app.core.security import current_user
from app.models import Card, User
from app.modules.albums import service
from app.modules.catalog.media_import import download_image, owned_image

router = APIRouter(tags=["Digital Album Color Extraction"])


def extract_colors(content: bytes) -> list[str]:
    settings = get_settings()
    if not content or len(content) > settings.scan_max_bytes:
        raise DomainError("ALBUM_COLOR_IMAGE_SIZE", "请选择不超过 15 MB 的图片", 422)
    try:
        with Image.open(io.BytesIO(content), formats=["JPEG", "PNG", "WEBP"]) as original:
            if original.width * original.height > settings.scan_max_pixels:
                raise DomainError("ALBUM_COLOR_IMAGE_SIZE", "图片像素过大，请缩小后重试", 422)
            image = ImageOps.exif_transpose(original).convert("RGBA")
            image.thumbnail((256, 256))
            # Ignore transparent borders rather than extracting their invisible RGB values.
            pixels = getattr(image, "get_flattened_data", image.getdata)()
            samples = [(r, g, b) for r, g, b, alpha in pixels if alpha >= 16]
            if not samples:
                raise DomainError(
                    "ALBUM_COLOR_EMPTY_IMAGE", "图片没有可见内容，未消耗取色次数", 422
                )
            strip = Image.new("RGB", (len(samples), 1))
            strip.putdata(samples)
            quantized = strip.quantize(colors=6, method=Image.Quantize.MEDIANCUT)
            palette = quantized.getpalette()
            colors = []
            for _, index in sorted(quantized.getcolors(), reverse=True):
                rgb = palette[index * 3 : index * 3 + 3]
                color = "#" + "".join(f"{component:02X}" for component in rgb)
                if color not in colors:
                    colors.append(color)
            return colors
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise DomainError(
            "ALBUM_COLOR_INVALID_IMAGE",
            "无法读取图片，请选择有效的 JPG、PNG 或 WebP 图片；未消耗取色次数",
            422,
        ) from exc


def card_image(db: Session, card_id: str) -> bytes:
    card = db.get(Card, card_id)
    if not service.card_available(card):
        raise DomainError("ALBUM_CARD_UNAVAILABLE", "只能从当前可用的官方小卡取色", 422)
    if not card.image_url or not owned_image(card.image_url):
        raise DomainError(
            "ALBUM_COLOR_IMAGE_UNAVAILABLE",
            "该小卡图片尚未入库，暂时无法取色；可以改选本机照片",
            422,
        )
    try:
        # Only a persisted, managed card image is read; there is no caller URL parameter.
        return download_image(card.image_url)
    except (OSError, ValueError) as exc:
        raise DomainError(
            "ALBUM_COLOR_IMAGE_UNAVAILABLE", "小卡图片暂不可用，未消耗取色次数", 422
        ) from exc


@router.post("/albums/color-extractions")
def analyze(
    request_id: str = Form(min_length=1, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$"),
    file: UploadFile | None = File(default=None),
    card_id: str | None = Form(default=None, min_length=1, max_length=64),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    if (file is None) == (card_id is None):
        raise DomainError("ALBUM_COLOR_INPUT_REQUIRED", "请选择一张照片或一张已有小卡", 422)
    # A database lock, not an in-process mutex, protects retries and multiple API workers.
    # The lock is shared with quota-affecting operations for this same user.
    service.lock_quota(db, user)
    cached = db.scalar(
        select(AlbumColorExtraction).where(
            AlbumColorExtraction.user_id == user.id,
            AlbumColorExtraction.request_id == request_id,
        )
    )
    if cached:
        result = {
            "request_id": request_id,
            "colors": cached.colors,
            "quota": service.quota(db, user),
        }
        db.commit()
        return success(result)
    quota = service.quota(db, user)["color_extraction"]
    if quota["daily_remaining"] <= 0 or quota["monthly_remaining"] <= 0:
        daily = quota["daily_remaining"] <= 0
        raise DomainError(
            "ALBUM_COLOR_QUOTA_EXCEEDED",
            "今日取色次数已用完，请明日再试" if daily else "本月取色次数已用完，请下月再试",
            409,
        )
    content = (
        file.file.read(get_settings().scan_max_bytes + 1)
        if file is not None
        else card_image(db, card_id)
    )
    colors = extract_colors(content)
    db.add(AlbumColorExtraction(user_id=user.id, request_id=request_id, colors=colors))
    db.flush()
    result = {"request_id": request_id, "colors": colors, "quota": service.quota(db, user)}
    db.commit()
    return success(result)
