"""Admin artwork lookup, including drafts; never replaces a matched card or its image."""

import io
import logging

from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import select

from app.common.response import DomainError
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.integrations.storage import get_storage
from app.models import Card

from .card_cropping import apply_crop, load_image, parse_crop
from .catalog_jobs import storage_bytes
from .catalog_service import admin_card, audit


def recognize(db, actor, raw, crop=None):
    confirmed = parse_crop(crop) if crop is not None else None
    if confirmed is not None:
        artwork = apply_crop(load_image(raw), confirmed)
    else:
        artwork = detect_single(raw)
    return recognize_artwork(db, actor, artwork, confirmed)


def detect_single(raw):
    try:
        image = Image.open(io.BytesIO(raw))
        if image.format not in {"JPEG", "PNG", "WEBP"} or image.width * image.height > 40_000_000:
            raise ValueError("Invalid image")
        image.load()
        image = ImageOps.exif_transpose(image).convert("RGB")
        normalized = io.BytesIO()
        image.save(normalized, format="PNG")
        regions = CardMatcherAdapter.detect(normalized.getvalue(), require_person=False)
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise DomainError("INVALID_IMAGE", "请上传有效的 JPG、PNG 或 WebP 小卡图片", 422) from exc
    except OverflowError as exc:
        raise DomainError("SINGLE_CARD_REQUIRED", "每次请上传一张小卡正面图片", 422) from exc
    if len(regions) != 1:
        raise DomainError("SINGLE_CARD_REQUIRED", "检测到多张小卡，请分别上传单张正面图片", 422)
    return regions[0].crop


def recognize_artwork(db, actor, artwork, confirmed=None):
    matcher = CardMatcherAdapter()
    cards = list(db.scalars(select(Card)))
    known = {c.id: c.image_url for c in cards if c.image_url}
    matcher.records = matcher.indexed(known)
    indexed = {r["card_id"] for r in matcher.records}
    unavailable = len(cards) - len(known)
    # Fill missing/stale admin entries in memory using only managed storage; include drafts.
    for card in cards:
        if not card.image_url or card.id in indexed:
            continue
        try:
            with Image.open(io.BytesIO(storage_bytes(card.image_url))) as reference:
                entry = matcher.index_entry(
                    card.id, ImageOps.exif_transpose(reference).convert("RGB"), card.image_url
                )
            matcher.records.append(entry)
        except (OSError, ValueError, OverflowError, Image.DecompressionBombError):
            unavailable += 1
    try:
        ranked = [r for r in matcher.rank(artwork, known) if r["similarity"] >= 0.6]
    except Exception as exc:
        logging.getLogger(__name__).exception("Admin card recognition failed")
        raise DomainError(
            "RECOGNITION_FAILED", "识别暂时失败，请重试；尚未新增或修改小卡", 503
        ) from exc
    score = ranked[0]["similarity"] if ranked else 0
    status = (
        "matched"
        if score >= 0.9 and (len(ranked) == 1 or score - ranked[1]["similarity"] >= 0.04)
        else "candidates"
        if ranked
        else "incomplete"
        if unavailable
        else "unrecognized"
    )
    buffer = io.BytesIO()
    artwork.save(buffer, format="WEBP", quality=95)
    image_url = get_storage().save_bytes(
        buffer.getvalue(), "card.webp", f"catalog/{actor.id}/recognition"
    )
    result = {
        "status": status,
        "image_url": image_url,
        "indexed_count": len(matcher.indexed(known)),
        "unavailable_count": unavailable,
        "candidates": [
            {"score": r["similarity"], "card": admin_card(db, db.get(Card, r["card_id"]))}
            for r in ranked
        ],
    }
    audit(
        db,
        actor,
        "catalog.card.recognize",
        "cards",
        "",
        None,
        {
            "status": status,
            "image_url": image_url,
            "candidate_ids": [r["card_id"] for r in ranked],
            "unavailable_count": unavailable,
            "crop": confirmed.model_dump() if confirmed else None,
        },
    )
    db.commit()
    return result
