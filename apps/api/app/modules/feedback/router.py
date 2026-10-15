import json
from typing import Any, Literal

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_admin, current_user
from app.models import DetectedCard, ScanFeedback, ScanSession, User
from app.modules.admin.catalog_extensions import CatalogRecord
from app.modules.admin.catalog_service import permit
from app.modules.feedback import fields, service
from app.modules.feedback.models import Feedback

router = APIRouter(prefix="/feedback", tags=["Catalog Feedback Workflow"])
admin_router = APIRouter(prefix="/admin/console/feedback", tags=["Catalog Feedback Review"])


class Change(BaseModel):
    model_config = ConfigDict(extra="forbid")
    key: str = Field(max_length=80)
    mode: Literal["SET", "CLEAR", "UNKNOWN"] = "SET"
    value: Any = None
    reason: str = Field(default="", max_length=1000)


class Submission(BaseModel):
    model_config = ConfigDict(extra="forbid")
    request_key: str = Field(min_length=8, max_length=100)
    kind: Literal["MISSING_CARD", "CORRECTION"]
    entity_type: str = "cards"
    entity_id: str = Field(default="", max_length=64)
    object_version: str = ""
    fields: list[Change] = Field(default_factory=list, max_length=20)
    missing: dict = Field(default_factory=dict)
    notes: str = Field(default="", max_length=2000)
    evidence_ids: list[str] = Field(default_factory=list, max_length=6)
    links: list[str] = Field(default_factory=list, max_length=6)

    @field_validator("missing")
    @classmethod
    def missing_safe(cls, value):
        for key, item in value.items():
            if key in {"is_group_pc", "is_double_sided"}:
                if not isinstance(item, bool):
                    raise ValueError("小卡属性必须为布尔值")
            elif item is not None and (not isinstance(item, str) or len(item) > 200):
                raise ValueError("小卡信息每项最多200字符")
        return value

    @field_validator("links")
    @classmethod
    def links_safe(cls, links):
        if any(len(v) > 800 or not v.startswith(("http://", "https://")) for v in links):
            raise ValueError("请填写HTTP(S)链接，最多800字符")
        return links


class Action(BaseModel):
    request_key: str = Field(min_length=8, max_length=100)
    revision: int = Field(ge=1)
    action: Literal["start", "review", "draft", "publish", "reject", "match", "already_fixed"]
    public_note: str = Field(default="", max_length=2000)
    internal_note: str = Field(default="", max_length=5000)
    card_id: str | None = None
    changes: dict = Field(default_factory=dict)
    decisions: list[dict] = Field(default_factory=list, max_length=20)
    object_version: str = ""
    sources: dict = Field(default_factory=dict)

    @field_validator("decisions")
    @classmethod
    def decisions_safe(cls, values):
        for d in values:
            if (
                set(d) - {"key", "decision", "value", "reason"}
                or d.get("decision") not in {"ACCEPT", "MODIFY", "REJECT"}
                or not isinstance(d.get("key"), str)
            ):
                raise ValueError("字段审核格式无效")
            if not isinstance(d.get("reason", ""), str) or len(d.get("reason", "")) > 2000:
                raise ValueError("原因最多2000字")
        return values


@router.get("/objects")
def objects(
    entity_type: str,
    q: str = Query("", max_length=120),
    parent_id: str | None = Query(None, max_length=64),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    return success({"items": fields.search_objects(db, entity_type, q, parent_id=parent_id)})


@router.get("/objects/{entity_type}/{entity_id}")
def object_fields(
    entity_type: str,
    entity_id: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    return success(fields.description(db, entity_type, entity_id))


@router.post("/images")
async def upload(
    file: UploadFile = File(...),
    crop: str | None = Form(None),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    try:
        bounds = json.loads(crop) if crop else None
    except ValueError as e:
        raise DomainError("INVALID_CROP", "裁剪参数无效", 422) from e
    if bounds is not None and (
        not isinstance(bounds, list)
        or len(bounds) != 4
        or any(not isinstance(v, (int, float)) for v in bounds)
    ):
        raise DomainError("INVALID_CROP", "裁剪参数无效", 422)
    asset = service.save_image(db, user, await file.read(10 * 1024 * 1024 + 1), bounds)
    db.commit()
    return success(
        {"id": asset.id, "image_url": asset.image_url, "version_identity": "USER_SUBMITTED"}
    )


class Crop(BaseModel):
    detected_card_id: str
    crop: list[float] = Field(min_length=4, max_length=4)


@router.post("/images/crop")
def crop_detected(body: Crop, user: User = Depends(current_user), db: Session = Depends(get_db)):
    detected = db.get(DetectedCard, body.detected_card_id)
    session = db.get(ScanSession, detected.scan_session_id) if detected else None
    if not session or session.user_id != user.id:
        raise DomainError("SCAN_NOT_FOUND", "扫描对象不存在", 404)
    try:
        content = service.get_storage().read_bytes(detected.crop_image_url)
    except Exception as e:
        raise DomainError("IMAGE_UNAVAILABLE", "原裁剪图不可用，请更换图片", 422) from e
    asset = service.save_image(db, user, content, body.crop)
    db.commit()
    return success(
        {"id": asset.id, "image_url": asset.image_url, "version_identity": "USER_SUBMITTED"}
    )


@router.post("")
def submit(body: Submission, user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = service.submit(db, user, body)
    db.commit()
    return success(service.payload(db, row))


def legacy_payload(db, row):
    from app.modules.scan.router import feedback_payload

    old = feedback_payload(db, row)
    return {
        "id": "legacy-" + row.id,
        "kind": "MISSING_CARD",
        "entity_type": "cards",
        "entity_id": (old.get("matched_card") or {}).get("id", ""),
        "name": old.get("idol_name") or "历史扫描反馈",
        "image_url": old.get("crop_image_url"),
        "created_at": old["created_at"],
        "updated_at": old["updated_at"],
        "status_label": {
            "pending": "待处理",
            "reviewing": "处理中",
            "resolved": "已处理",
            "rejected": "未收录",
            "ignored": "未收录",
        }.get(row.status, "已处理"),
        "status": row.status,
        "result": "PENDING",
        "public_note": old.get("review_reason") or "历史反馈，未记录图片采用事实",
        "submission": {"notes": old.get("notes")},
        "history": [],
        "decisions": [],
        "target_available": bool(old.get("matched_card")),
    }


def legacy_catalog_payload(db, row):
    available = False
    try:
        obj = fields.description(db, row.entity_type, row.entity_id)
        available = True
    except DomainError:
        obj = {}
    suggested = row.data.get("suggested", {})
    public_fields = []
    for key, label, editor, *_ in fields.FIELDS.get(row.entity_type, []):
        if key in suggested:
            public_fields.append(
                {
                    "key": key,
                    "label": label,
                    "type": editor,
                    "current": None,
                    "suggested": suggested[key],
                    "mode": "SET",
                    "reason": "历史提交未保存当前值快照",
                }
            )
    return {
        "id": "legacy-catalog-" + row.id,
        "kind": "CORRECTION",
        "entity_type": row.entity_type,
        "entity_id": row.entity_id,
        "name": obj.get("name") or suggested.get("name") or "历史图鉴补充",
        "image_url": obj.get("image_url") or suggested.get("image_url"),
        "created_at": row.created_at.isoformat(),
        "updated_at": row.updated_at.isoformat(),
        "status": "PENDING" if row.status == "PENDING" else "PROCESSED",
        "result": {"ACCEPTED": "INCLUDED", "REJECTED": "NOT_INCLUDED"}.get(row.status, "PENDING"),
        "status_label": {"ACCEPTED": "已收录", "REJECTED": "已处理"}.get(row.status, "待处理"),
        "public_note": row.data.get("review_reason") or "历史图鉴补充记录",
        "submission": {"notes": row.data.get("reason", ""), "fields": public_fields},
        "history": [],
        "decisions": [],
        "target_available": available,
    }


@router.get("")
def history(
    kind: str | None = None,
    offset: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=50),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    query = select(Feedback).where(Feedback.user_id == user.id)
    if kind:
        query = query.where(Feedback.kind == kind)
    rows = [service.payload(db, r) for r in db.scalars(query)]
    if kind in {None, "MISSING_CARD"}:
        rows.extend(
            legacy_payload(db, r)
            for r in db.scalars(select(ScanFeedback).where(ScanFeedback.user_id == user.id))
        )
    if kind in {None, "CORRECTION"}:
        rows.extend(
            legacy_catalog_payload(db, r)
            for r in db.scalars(
                select(CatalogRecord).where(
                    CatalogRecord.kind == "reviews",
                    CatalogRecord.data["contributor"].as_string() == user.id,
                )
            )
        )
    rows.sort(key=lambda r: (r["created_at"], r["id"]), reverse=True)
    return success(
        {
            "items": rows[offset : offset + limit],
            "next_offset": offset + limit if len(rows) > offset + limit else None,
        }
    )


@router.get("/records/{feedback_id}")
def detail(feedback_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if feedback_id.startswith("legacy-catalog-"):
        row = db.get(CatalogRecord, feedback_id.removeprefix("legacy-catalog-"))
        if not row or row.kind != "reviews" or row.data.get("contributor") != user.id:
            raise DomainError("NOT_FOUND", "反馈不存在", 404)
        return success(legacy_catalog_payload(db, row))
    if feedback_id.startswith("legacy-"):
        row = db.get(ScanFeedback, feedback_id.removeprefix("legacy-"))
        if not row or row.user_id != user.id:
            raise DomainError("NOT_FOUND", "反馈不存在", 404)
        return success(legacy_payload(db, row))
    row = db.get(Feedback, feedback_id)
    if not row or row.user_id != user.id:
        raise DomainError("NOT_FOUND", "反馈不存在", 404)
    return success(service.payload(db, row))


@router.get("/cards/{card_id}/contributors")
def contributors(card_id: str, db: Session = Depends(get_db)):
    fields.target(db, "cards", card_id)
    return success({"items": service.credits(db, card_id)})


@router.get("/users/{user_id}/contributions")
def contributions(
    user_id: str,
    offset: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=50),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    return success(
        service.contributions(db, user.id if user_id == "me" else user_id, offset, limit)
    )


@admin_router.get("")
def queue(
    kind: Literal["MISSING_CARD", "CORRECTION"],
    status: str | None = None,
    result: str | None = None,
    entity_type: str | None = None,
    handler_id: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    offset: int = Query(0, ge=0),
    limit: int = Query(30, ge=1, le=100),
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "catalog")
    query = select(Feedback).where(Feedback.kind == kind)
    for column, value in [
        (Feedback.status, status),
        (Feedback.result, result),
        (Feedback.entity_type, entity_type),
        (Feedback.handler_id, handler_id),
    ]:
        if value:
            query = query.where(column == value)
    if date_from:
        query = query.where(Feedback.created_at >= date_from)
    if date_to:
        query = query.where(Feedback.created_at <= date_to + "T23:59:59")
    rows = db.scalars(
        query.order_by(Feedback.created_at.desc()).offset(offset).limit(limit + 1)
    ).all()
    return success(
        {
            "items": [service.payload(db, r, True) for r in rows[:limit]],
            "next_offset": offset + limit if len(rows) > limit else None,
        }
    )


@admin_router.get("/{feedback_id}")
def review_detail(
    feedback_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    permit(actor, "catalog")
    row = db.get(Feedback, feedback_id)
    if not row:
        raise DomainError("NOT_FOUND", "反馈不存在", 404)
    return success(service.payload(db, row, True))


@admin_router.post("/{feedback_id}/actions")
def action(
    feedback_id: str,
    body: Action,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    row = db.get(Feedback, feedback_id)
    if not row:
        raise DomainError("NOT_FOUND", "反馈不存在", 404)
    try:
        service.act(db, row, actor, body)
        db.commit()
    except (DomainError, ValidationError) as caught:
        error = (
            caught
            if isinstance(caught, DomainError)
            else DomainError("INVALID_VALUE", "发布资料格式不完整，请检查所选字段", 422)
        )
        db.rollback()
        if body.action == "publish" and error.error_code in {
            "FIELD_VALIDATION_ERROR",
            "IMAGE_UNAVAILABLE",
            "COPYRIGHT_REQUIRED",
            "VALUE_REQUIRED",
            "INVALID_VALUE",
        }:
            row = db.get(Feedback, feedback_id)
            if row.revision != body.revision or row.result != "PENDING":
                raise error from caught
            row.internal_note = f"发布校验失败：{error.message}"
            row.status = "PROCESSED"
            row.review = {**row.review, "retry_changes": body.changes, "decisions": body.decisions}
            service.event(db, row, "审核已处理，待完成发布校验")
            db.commit()
        raise error from caught
    service.deliver_notices(db)
    return success(service.payload(db, row, True))
