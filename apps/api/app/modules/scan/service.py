from __future__ import annotations

import io
import logging
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.common.response import DomainError
from app.common.serializers import card_payload
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.integrations.card_matcher.portrait_detector import PortraitDetectorUnavailable
from app.integrations.storage import get_storage
from app.models import (
    Card,
    DetectedCard,
    ScanCandidate,
    ScanSession,
    User,
    UserCollectionItem,
    UserWishlistItem,
)
from app.modules.scan.schemas import ScanConfirmRequest


def known_cards(db: Session) -> dict[str, str | None]:
    return dict(
        db.execute(
            select(Card.id, Card.image_url).where(Card.status.in_(["PUBLISHED", "OFFLINE"]))
        ).all()
    )


def readiness(db: Session) -> dict[str, Any]:
    return CardMatcherAdapter().readiness(known_cards(db))


def detect(db: Session, user: User, content: bytes) -> dict[str, Any]:
    """Locate cards only. Matching and collection writes require separate user actions."""
    from PIL import Image, ImageOps

    try:
        regions = CardMatcherAdapter.detect(content)
    except PortraitDetectorUnavailable as exc:
        raise DomainError(
            "SCAN_DETECTOR_UNAVAILABLE", "人物检测服务暂未就绪，请稍后重试", 503
        ) from exc
    except OverflowError as exc:
        raise DomainError("TOO_MANY_CARDS", "一次最多扫描 10 张小卡，请分批拍摄") from exc
    except Exception as exc:
        raise DomainError("INVALID_SCAN_IMAGE", "无法读取图片，请重新选择") from exc
    original = ImageOps.exif_transpose(Image.open(io.BytesIO(content))).convert("RGB")
    buffer = io.BytesIO()
    original.save(buffer, format="JPEG", quality=90)
    storage = get_storage()
    session = ScanSession(
        user_id=user.id,
        status="detected",
        original_image_url=storage.save_bytes(buffer.getvalue(), "scan.jpg", f"scans/{user.id}"),
    )
    db.add(session)
    db.flush()
    for region in regions:
        buffer = io.BytesIO()
        region.crop.save(buffer, format="JPEG", quality=90)
        db.add(
            DetectedCard(
                scan_session_id=session.id,
                crop_image_url=storage.save_bytes(
                    buffer.getvalue(), "crop.jpg", f"scans/{user.id}/{session.id}"
                ),
                crop_region=region.payload(),
                recognition_status="detected",
            )
        )
        db.flush()
    db.commit()
    return {
        **session_payload(db, session, include_pending=True),
        "image_width": original.width,
        "image_height": original.height,
    }


def recognize_selection(db: Session, user: User, session_id: str, ids: list[str]) -> dict[str, Any]:
    from PIL import Image

    session = db.scalar(
        select(ScanSession)
        .where(ScanSession.id == session_id, ScanSession.user_id == user.id)
        .with_for_update()
    )
    if session is None:
        raise DomainError("SCAN_NOT_FOUND", "扫描记录不存在", 404)
    regions = db.scalars(
        select(DetectedCard)
        .where(DetectedCard.scan_session_id == session.id)
        .order_by(DetectedCard.created_at)
    ).all()
    if not ids or not set(ids).issubset({region.id for region in regions}):
        raise DomainError("INVALID_SCAN_SELECTION", "请选择本次照片中的小卡")
    matched_ids = {r.id for r in regions if r.recognition_status != "detected"}
    if session.status == "completed":
        if set(ids) != matched_ids:
            raise DomainError("SCAN_ALREADY_COMPLETED", "本次扫描已完成，请重新拍摄", 409)
        return session_payload(db, session)
    matcher = CardMatcherAdapter()
    cards = known_cards(db)
    if not matcher.readiness(cards)["available"]:
        raise DomainError("SCAN_INDEX_UNAVAILABLE", "图鉴识别服务暂未就绪，请稍后重试", 503)
    storage = get_storage()
    for region in regions:
        if region.id not in ids:
            continue
        try:
            image = Image.open(io.BytesIO(storage.read_bytes(region.crop_image_url))).convert("RGB")
        except Exception as exc:
            # Roll back the entire matching transaction, retaining the detection session for retry.
            raise DomainError(
                "SCAN_IMAGE_UNAVAILABLE", "扫描照片暂时无法读取，请重试或重新拍摄", 503
            ) from exc
        try:
            ranked = matcher.rank(image, cards)
        except Exception:
            logging.getLogger(__name__).exception("One selected scan region could not be matched")
            ranked = []
        score = ranked[0]["similarity"] if ranked else 0.0
        region.recognition_status = (
            "recommended"
            if score >= 0.9 and (len(ranked) == 1 or score - ranked[1]["similarity"] >= 0.04)
            else "needs_confirmation"
            if score >= 0.6
            else "unrecognized"
        )
        for rank, candidate in enumerate(ranked, start=1):
            db.add(
                ScanCandidate(
                    detected_card_id=region.id,
                    card_id=candidate["card_id"],
                    similarity=candidate["similarity"],
                    feature_scores=candidate["feature_scores"],
                    rank=rank,
                )
            )
    session.status = "completed"
    db.commit()
    return session_payload(db, session)


def recognize(db: Session, user: User, content: bytes, filename: str) -> dict[str, Any]:
    matcher = CardMatcherAdapter()
    cards = known_cards(db)
    if not matcher.readiness(cards)["available"]:
        raise DomainError(
            "SCAN_INDEX_UNAVAILABLE", "图鉴尚未建立可用卡图索引，请先上传卡片正面并生成索引", 503
        )
    try:
        regions = matcher.detect(content)
    except PortraitDetectorUnavailable as exc:
        raise DomainError(
            "SCAN_DETECTOR_UNAVAILABLE", "人物检测服务暂未就绪，请稍后重试", 503
        ) from exc
    except OverflowError as exc:
        raise DomainError("TOO_MANY_CARDS", "一次最多识别 10 张小卡，请分批扫描") from exc
    except Exception as exc:
        raise DomainError("INVALID_SCAN_IMAGE", "无法读取图片，请重新选择") from exc
    # Normalize EXIF orientation and media format for browser/mobile image decoders.
    from PIL import Image, ImageOps

    original = ImageOps.exif_transpose(Image.open(io.BytesIO(content))).convert("RGB")
    buffer = io.BytesIO()
    original.save(buffer, format="JPEG", quality=90)
    original_url = get_storage().save_bytes(buffer.getvalue(), "scan.jpg", f"scans/{user.id}")
    session = ScanSession(user_id=user.id, original_image_url=original_url)
    db.add(session)
    db.flush()
    for region in regions:
        crop_buffer = io.BytesIO()
        region.crop.save(crop_buffer, format="JPEG", quality=90)
        crop_url = get_storage().save_bytes(
            crop_buffer.getvalue(), "crop.jpg", f"scans/{user.id}/{session.id}"
        )
        try:
            ranked = matcher.rank(region.crop, cards)
        except Exception:
            logging.getLogger(__name__).exception("One scan region could not be matched")
            ranked = []
        top_score = ranked[0]["similarity"] if ranked else 0.0
        status = (
            "recommended"
            if top_score >= 0.9
            and (len(ranked) == 1 or top_score - ranked[1]["similarity"] >= 0.04)
            else "needs_confirmation"
            if top_score >= 0.6
            else "unrecognized"
        )
        detected = DetectedCard(
            scan_session_id=session.id,
            crop_image_url=crop_url,
            crop_region=region.payload(),
            recognition_status=status,
        )
        db.add(detected)
        db.flush()
        for rank, candidate in enumerate(ranked, start=1):
            db.add(
                ScanCandidate(
                    detected_card_id=detected.id,
                    card_id=candidate["card_id"],
                    similarity=candidate["similarity"],
                    feature_scores=candidate["feature_scores"],
                    rank=rank,
                )
            )
    db.commit()
    return session_payload(db, session)


def session_payload(
    db: Session,
    session: ScanSession,
    include_server_images: bool = True,
    *,
    include_pending: bool = False,
) -> dict[str, Any]:
    detected_cards = db.scalars(
        select(DetectedCard)
        .where(DetectedCard.scan_session_id == session.id)
        .order_by(DetectedCard.created_at)
    ).all()
    result = []
    for detected in detected_cards:
        if detected.recognition_status == "detected" and not include_pending:
            continue
        candidates = db.scalars(
            select(ScanCandidate)
            .where(ScanCandidate.detected_card_id == detected.id)
            .order_by(ScanCandidate.rank)
        ).all()
        candidate_payloads = []
        for item in candidates:
            card = db.get(Card, item.card_id)
            if card is not None and card.status in {"PUBLISHED", "OFFLINE"}:
                candidate_payloads.append(
                    {
                        "similarity": item.similarity,
                        "scores": item.feature_scores,
                        "card": card_payload(db, card),
                    }
                )
        # Manual catalog choices need their artwork/details in history too,
        # without inventing an AI similarity score.
        if detected.user_confirmed_card_id and not any(
            item["card"]["id"] == detected.user_confirmed_card_id for item in candidate_payloads
        ):
            confirmed = db.get(Card, detected.user_confirmed_card_id)
            if confirmed is not None and confirmed.status in {"PUBLISHED", "OFFLINE"}:
                candidate_payloads.append(
                    {"similarity": 0, "scores": {}, "card": card_payload(db, confirmed)}
                )
        result.append(
            {
                "detected_card_id": detected.id,
                "crop_image_path": detected.crop_image_url if include_server_images else None,
                "crop_region": detected.crop_region,
                "recognition_status": detected.recognition_status,
                "user_confirmed_card_id": detected.user_confirmed_card_id,
                "owned_added": detected.owned_added_at is not None,
                "candidates": candidate_payloads,
            }
        )
    return {
        "session_id": session.id,
        "original_image_path": session.original_image_url if include_server_images else None,
        "detected_cards": result,
    }


def confirm(
    db: Session, user: User, session: ScanSession, payload: ScanConfirmRequest
) -> dict[str, Any]:
    if session.user_id != user.id:
        raise DomainError("SCAN_NOT_FOUND", "扫描记录不存在", 404)
    # Serialize confirmations for one user on PostgreSQL. SQLite obtains its
    # write lock at the conditional claim below; the claim also makes retries safe.
    db.execute(select(User.id).where(User.id == user.id).with_for_update())
    added = 0
    quantities: dict[str, int] = {}
    for item in payload.cards:
        detected = db.get(DetectedCard, item.detected_card_id)
        if detected is None or detected.scan_session_id != session.id:
            raise DomainError("DETECTED_CARD_NOT_FOUND", "识别对象不存在", 404)
        card = db.get(Card, item.card_id)
        if card is None or card.status not in {"PUBLISHED", "OFFLINE"}:
            raise DomainError("CARD_NOT_FOUND", "小卡不存在", 404)
        if detected.owned_added_at and detected.user_confirmed_card_id != item.card_id:
            raise DomainError("SCAN_ALREADY_ADDED", "此扫描对象已加入收藏，请在收藏中修改", 409)
        if item.selected:
            claim = db.execute(
                update(DetectedCard)
                .where(DetectedCard.id == detected.id, DetectedCard.owned_added_at.is_(None))
                .values(owned_added_at=datetime.now(UTC), user_confirmed_card_id=item.card_id)
            )
            if not claim.rowcount:
                db.refresh(detected)
                if detected.user_confirmed_card_id != item.card_id:
                    raise DomainError(
                        "SCAN_ALREADY_ADDED", "此扫描对象已加入收藏，请在收藏中修改", 409
                    )
            owned = db.scalar(
                select(UserCollectionItem).where(
                    UserCollectionItem.user_id == user.id,
                    UserCollectionItem.card_id == item.card_id,
                )
            )
            if claim.rowcount:
                if owned:
                    owned.quantity += 1
                else:
                    owned = UserCollectionItem(user_id=user.id, card_id=item.card_id, quantity=1)
                    db.add(owned)
                added += 1
            quantities[item.card_id] = owned.quantity if owned else 0
        else:
            db.execute(
                update(DetectedCard)
                .where(DetectedCard.id == detected.id, DetectedCard.owned_added_at.is_(None))
                .values(user_confirmed_card_id=item.card_id)
            )
        if item.add_to_wishlist:
            wished = db.scalar(
                select(UserWishlistItem).where(
                    UserWishlistItem.user_id == user.id, UserWishlistItem.card_id == item.card_id
                )
            )
            if wished is None:
                db.add(UserWishlistItem(user_id=user.id, card_id=item.card_id))
        db.flush()
    db.commit()
    return {"added_count": added, "quantities": quantities}
