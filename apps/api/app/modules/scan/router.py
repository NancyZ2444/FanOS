from __future__ import annotations

from hashlib import sha256
from typing import Literal

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.admin_models import ContentMetadata
from app.common.response import DomainError, success
from app.common.serializers import card_payload
from app.core.config import get_settings
from app.core.database import get_db
from app.core.security import current_user
from app.models import (
    Card,
    CatalogAlbum,
    CatalogEvent,
    DetectedCard,
    Group,
    GroupMembership,
    Idol,
    ScanCandidate,
    ScanFeedback,
    ScanSession,
    User,
)
from app.modules.catalog.taxonomy_models import CatalogOther
from app.modules.scan import service
from app.modules.scan.schemas import ScanConfirmRequest, ScanFeedbackMetadata, ScanSelectionRequest

router = APIRouter(prefix="/scan", tags=["AI Scan"])

SOURCE_KINDS = {
    "专辑": ("ALBUM", "albums", CatalogAlbum),
    "签售": ("EVENT", "events", CatalogEvent),
    "演唱会": ("EVENT", "events", CatalogEvent),
    "活动": ("EVENT", "events", CatalogEvent),
    "其他": ("OTHER", "others", CatalogOther),
}
SourceCategory = Literal["专辑", "活动", "签售", "演唱会", "不确定", "其他"]


def _source_name(row) -> str:
    """Use the same localized name priority as the public catalog, not client labels."""
    names = [getattr(row, "name_en", ""), getattr(row, "name_ko", "")]
    return " · ".join(dict.fromkeys(name for name in names if name)) or (
        getattr(row, "name_translated", "") or row.name
    )


def _entity_metadata(db: Session, kind: str, entity_id: str) -> ContentMetadata | None:
    return db.scalar(
        select(ContentMetadata).where(
            ContentMetadata.entity_type == kind, ContentMetadata.entity_id == entity_id
        )
    )


def _validate_feedback_actors(db: Session, group_id: str | None, idol_id: str | None) -> None:
    for kind, item_id, model in (("groups", group_id, Group), ("idols", idol_id, Idol)):
        if not item_id:
            continue
        meta = _entity_metadata(db, kind, item_id)
        if db.get(model, item_id) is None or (meta and meta.status != "PUBLISHED"):
            raise DomainError("INVALID_FEEDBACK", "组合或艺人不存在或尚未发布")
    if group_id and idol_id:
        membership = db.scalar(
            select(GroupMembership).where(
                GroupMembership.group_id == group_id, GroupMembership.idol_id == idol_id
            )
        )
        if membership is None:
            raise DomainError("INVALID_FEEDBACK", "请选择所属组合的成员")


def _source_matches(
    db: Session, source: str, kind: str, row, group_id: str | None, idol_id: str | None
) -> bool:
    meta = _entity_metadata(db, kind, row.id)
    if not row.is_published or (meta and meta.status != "PUBLISHED"):
        return False
    if kind == "others":
        return True
    if source in {"签售", "演唱会"}:
        event_type = row.event_type.casefold().replace(" ", "").replace("-", "")
        allowed = (
            {"签售", "签售会", "fansign", "fansigning", "fancall", "videocall"}
            if source == "签售"
            else {"演唱会", "巡演", "concert", "tour", "livetour", "live", "concerttour"}
        )
        if event_type not in allowed:
            return False
    data = meta.data if meta else {}
    actors = data.get("artists") or (
        [{"type": "idols", "id": data["idol_id"]}]
        if data.get("idol_id")
        else [{"type": "groups", "id": row.group_id}]
        if row.group_id
        else []
    )
    actor_groups = {a.get("id") for a in actors if a.get("type") in {"groups", "group"}}
    actor_idols = {a.get("id") for a in actors if a.get("type") in {"idols", "idol"}}
    if group_id and group_id not in actor_groups:
        if (
            not actor_idols
            or db.scalar(
                select(GroupMembership.id).where(
                    GroupMembership.group_id == group_id, GroupMembership.idol_id.in_(actor_idols)
                )
            )
            is None
        ):
            return False
    if idol_id and idol_id not in actor_idols:
        if (
            not actor_groups
            or db.scalar(
                select(GroupMembership.id).where(
                    GroupMembership.idol_id == idol_id, GroupMembership.group_id.in_(actor_groups)
                )
            )
            is None
        ):
            return False
    return True


def _legacy_version_id(source_id: str, name: str) -> str:
    digest = sha256(f"{source_id}\0{name}".encode()).hexdigest()[:32]
    return f"legacy_version_{digest}"


def _source_versions(db: Session, kind: str, row) -> list[dict[str, str]]:
    from app.modules.admin.catalog_extensions import CatalogRecord

    records = db.scalars(
        select(CatalogRecord)
        .where(
            CatalogRecord.kind == "versions",
            CatalogRecord.entity_type == kind,
            CatalogRecord.entity_id == row.id,
        )
        .order_by(CatalogRecord.created_at, CatalogRecord.id)
    ).all()
    result = [
        {"id": record.id, "name": str(record.data["name"])}
        for record in records
        if record.status not in {"ARCHIVED", "OFFLINE"} and record.data.get("name")
    ]
    # Legacy arrays have no version IDs. Expose stable read-only references rather
    # than create operational records from a public GET. All IDs are revalidated.
    structural_names = {str(record.data.get("name", "")).casefold() for record in records}
    for name in getattr(row, "versions", []) or []:
        if isinstance(name, str) and name and name.casefold() not in structural_names:
            result.append({"id": _legacy_version_id(row.id, name), "name": name})
            structural_names.add(name.casefold())
    return result


def _validate_source_reference(db: Session, payload: dict) -> dict:
    source = payload.get("source")
    mode = payload.get("source_mode") or ("UNCERTAIN" if source == "不确定" else "KNOWN")
    result = {"source_mode": mode, "source_name": None, "source_version_name": None}
    if mode == "UNCERTAIN":
        if source not in {None, "不确定"}:
            raise DomainError("INVALID_FEEDBACK", "不确定来源请不要关联具体来源类型")
        payload["source"] = "不确定"
    if mode in {"UNCERTAIN", "OTHER"}:
        if payload.get("source_entity_id"):
            raise DomainError("INVALID_FEEDBACK", "其他或不确定来源不能关联官方条目")
        return result
    if not payload.get("source_entity_id"):
        return result  # A category-only submission remains valid for older apps.
    config = SOURCE_KINDS.get(source)
    if config is None or payload["source_entity_type"] != config[0]:
        raise DomainError("INVALID_FEEDBACK", "所选官方条目与来源类型不一致")
    _, kind, model = config
    row = db.get(model, payload["source_entity_id"])
    if row is None or not _source_matches(
        db, source, kind, row, payload.get("group_id"), payload.get("idol_id")
    ):
        raise DomainError("INVALID_FEEDBACK", "来源不存在、尚未发布或不属于所选组合/艺人")
    result["source_name"] = _source_name(row)
    if version_id := payload.get("source_version_id"):
        versions = _source_versions(db, kind, row)
        version = next((v for v in versions if v["id"] == version_id), None)
        if version is None and str(version_id).startswith("legacy_version_"):
            from app.modules.admin.album_versions import version_key

            # Saving an operator draft materializes legacy names into real version
            # records. Keep previously submitted references usable for resubmission,
            # while resolving only within this source and its currently active versions.
            legacy_names = {
                version_key(name)
                for name in getattr(row, "versions", []) or []
                if isinstance(name, str) and version_id == _legacy_version_id(row.id, name)
            }
            matches = [v for v in versions if version_key(v["name"]) in legacy_names]
            if len(matches) == 1:
                version = matches[0]
        if version is None:
            raise DomainError("INVALID_FEEDBACK", "版本不存在、已归档或不属于所选来源")
        result["source_version_id"] = version["id"]
        result["source_version_name"] = version["name"]
    return result


@router.get("/feedback-options")
def feedback_options(
    source: SourceCategory,
    group_id: str | None = Query(default=None, max_length=100),
    idol_id: str | None = Query(default=None, max_length=100),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    _validate_feedback_actors(db, group_id, idol_id)
    mode = "UNCERTAIN" if source == "不确定" else "KNOWN"
    items = []
    if config := SOURCE_KINDS.get(source):
        entity_type, kind, model = config
        for row in db.scalars(select(model).where(model.is_published.is_(True))).all():
            if _source_matches(db, source, kind, row, group_id, idol_id):
                items.append(
                    {
                        "id": row.id,
                        "name": _source_name(row),
                        "entity_type": entity_type,
                        "subtitle": " · ".join(
                            part
                            for part in (
                                getattr(row, "artist_name", ""),
                                getattr(row, "release_date", getattr(row, "start_date", "")),
                            )
                            if part
                        ),
                        "versions": _source_versions(db, kind, row),
                    }
                )
        items.sort(key=lambda item: (item["name"].casefold(), item["id"]))
    return success({"source": source, "source_mode": mode, "items": items})


def feedback_payload(db: Session, row: ScanFeedback) -> dict:
    data = row.payload or {}
    card = db.get(Card, data.get("matched_card_id")) if data.get("matched_card_id") else None
    group = db.get(Group, row.group_id) if row.group_id else None
    idol = db.get(Idol, row.idol_id) if row.idol_id else None
    return {
        "id": row.id,
        "scan_session_id": row.scan_session_id,
        "detected_card_id": row.detected_card_id,
        "status": row.status,
        "created_at": row.created_at.isoformat(),
        "updated_at": row.updated_at.isoformat(),
        "original_image_url": data.get("original_image_url"),
        "crop_image_url": data.get("crop_image_url"),
        "group_name": group.name if group else None,
        "idol_name": idol.name if idol else None,
        "group_id": row.group_id,
        "idol_id": row.idol_id,
        "source": row.source,
        "source_mode": data.get("source_mode")
        or (
            "UNCERTAIN" if row.source == "不确定" else "OTHER" if row.source == "其他" else "KNOWN"
        ),
        "source_entity_type": data.get("source_entity_type"),
        "source_entity_id": data.get("source_entity_id"),
        "source_version_id": data.get("source_version_id"),
        "source_name": data.get("source_name"),
        "source_version_name": data.get("source_version_name"),
        "notes": row.notes,
        "review_reason": data.get("review_reason"),
        "matched_card": card_payload(db, card)
        if card and card.status in {"PUBLISHED", "OFFLINE"}
        else None,
    }


@router.get("/feedback")
def feedback_history(
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=50),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    rows = db.scalars(
        select(ScanFeedback)
        .where(ScanFeedback.user_id == user.id)
        .order_by(ScanFeedback.created_at.desc(), ScanFeedback.id.desc())
        .offset(offset)
        .limit(limit + 1)
    ).all()
    return success(
        {
            "items": [feedback_payload(db, row) for row in rows[:limit]],
            "next_offset": offset + limit if len(rows) > limit else None,
        }
    )


@router.get("/feedback/{feedback_id}")
def feedback_detail(
    feedback_id: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    row = db.get(ScanFeedback, feedback_id)
    if row is None or row.user_id != user.id:
        raise DomainError("FEEDBACK_NOT_FOUND", "反馈记录不存在", 404)
    return success(feedback_payload(db, row))


@router.get("/status")
def scan_status(db: Session = Depends(get_db)) -> dict:
    return success(service.readiness(db))


@router.post("/recognize")
async def recognize(
    image: UploadFile = File(...), user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    content = await image.read(get_settings().scan_max_bytes + 1)
    if not content:
        raise DomainError("EMPTY_FILE", "图片不能为空")
    if len(content) > get_settings().scan_max_bytes:
        raise DomainError("SCAN_IMAGE_TOO_LARGE", "图片不能超过 15 MB", 413)
    return success(
        await run_in_threadpool(service.recognize, db, user, content, image.filename or "scan.jpg")
    )


@router.post("/detect")
async def detect_cards(
    image: UploadFile = File(...), user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    content = await image.read(get_settings().scan_max_bytes + 1)
    if not content:
        raise DomainError("EMPTY_FILE", "图片不能为空")
    if len(content) > get_settings().scan_max_bytes:
        raise DomainError("SCAN_IMAGE_TOO_LARGE", "图片不能超过 15 MB", 413)
    return success(await run_in_threadpool(service.detect, db, user, content))


@router.post("/sessions/{session_id}/recognize")
def recognize_selected_cards(
    session_id: str,
    payload: ScanSelectionRequest,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    return success(service.recognize_selection(db, user, session_id, payload.detected_card_ids))


@router.post("/sessions/{session_id}/confirm")
def confirm_session(
    session_id: str,
    payload: ScanConfirmRequest,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    session = db.get(ScanSession, session_id)
    if session is None:
        raise DomainError("SCAN_NOT_FOUND", "扫描记录不存在", 404)
    return success(service.confirm(db, user, session, payload))


@router.get("/history")
def scan_history(user: User = Depends(current_user), db: Session = Depends(get_db)) -> dict:
    sessions = db.scalars(
        select(ScanSession)
        .where(ScanSession.user_id == user.id, ScanSession.status == "completed")
        .order_by(ScanSession.created_at.desc())
        .limit(50)
    ).all()
    return success({"items": [service.session_payload(db, item) for item in sessions]})


async def submit_feedback(
    metadata: str = Form(...),
    original_image: UploadFile | None = File(default=None),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    try:
        payload = ScanFeedbackMetadata.model_validate_json(metadata).model_dump()
    except ValidationError as exc:
        raise DomainError("INVALID_FEEDBACK", "反馈数据格式不正确") from exc
    session = db.get(ScanSession, payload.get("scan_session_id"))
    detected = db.get(DetectedCard, payload.get("detected_card_id"))
    if (
        session is None
        or detected is None
        or session.user_id != user.id
        or detected.scan_session_id != session.id
    ):
        raise DomainError("SCAN_NOT_FOUND", "扫描记录不存在", 404)
    _validate_feedback_actors(db, payload.get("group_id"), payload.get("idol_id"))
    source_details = _validate_source_reference(db, payload)
    candidates = db.scalars(
        select(ScanCandidate).where(ScanCandidate.detected_card_id == detected.id)
    ).all()
    # Trust persisted recognition data, never the client's claimed identity/scores.
    payload = {
        key: payload.get(key)
        for key in (
            "group_id",
            "idol_id",
            "source",
            "notes",
            "source_mode",
            "source_entity_type",
            "source_entity_id",
            "source_version_id",
        )
    }
    payload.update(source_details)
    payload.update(
        {
            "scan_session_id": session.id,
            "detected_card_id": detected.id,
            "user_id": user.id,
            "original_image_url": session.original_image_url,
            "crop_image_url": detected.crop_image_url,
            "crop_region": detected.crop_region,
            "ai_candidates": [
                {"card_id": row.card_id, "similarity": row.similarity} for row in candidates
            ],
        }
    )
    feedback = ScanFeedback(
        scan_session_id=session.id,
        detected_card_id=detected.id,
        user_id=user.id,
        group_id=payload.get("group_id"),
        idol_id=payload.get("idol_id"),
        source=payload.get("source"),
        notes=payload.get("notes"),
        payload=payload,
    )
    db.add(feedback)
    db.commit()
    return success({"feedback_id": feedback.id}, "感谢反馈，我们会尽快补充图鉴。")
