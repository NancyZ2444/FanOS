"""Additive catalog operational records; legacy entity IDs remain authoritative."""

from __future__ import annotations

from datetime import date
from typing import Any

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import JSON, String, UniqueConstraint, select
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.common.response import DomainError, success
from app.core.database import Base, get_db
from app.core.security import current_admin, current_user
from app.models import (
    Card,
    Group,
    GroupMembership,
    Idol,
    OperationLog,
    TimestampMixin,
    User,
    new_id,
)


class CatalogRecord(Base, TimestampMixin):
    __tablename__ = "catalog_operational_records"
    __table_args__ = (UniqueConstraint("kind", "id"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("cat"))
    kind: Mapped[str] = mapped_column(String(40), index=True)
    entity_type: Mapped[str] = mapped_column(String(40), default="", index=True)
    entity_id: Mapped[str] = mapped_column(String(64), default="", index=True)
    status: Mapped[str] = mapped_column(String(30), default="DRAFT", index=True)
    data: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)


class RecordDraft(BaseModel):
    entity_type: str = ""
    entity_id: str = ""
    status: str = "DRAFT"
    data: dict = Field(default_factory=dict)


router = APIRouter(prefix="/admin/console", tags=["Catalog Operations"])
contribution_router = APIRouter(prefix="/catalog", tags=["Catalog Feedback"])


class Contribution(BaseModel):
    entity_type: str
    entity_id: str = ""
    reason: str = Field(min_length=1, max_length=1000)
    suggested: dict = Field(default_factory=dict)
    evidence_image: str = ""
    source_url: str = ""

    @field_validator("evidence_image", "source_url")
    @classmethod
    def safe_link(cls, value: str) -> str:
        if value and not value.startswith(("http://", "https://", "/media/")):
            raise ValueError("请提供有效的 HTTP(S) 链接")
        return value


def contribution(
    payload: Contribution, actor: User = Depends(current_user), db: Session = Depends(get_db)
):
    from .catalog_service import MODELS

    if payload.entity_type not in {*MODELS, "cards"}:
        raise DomainError("INVALID_ENTITY_TYPE", "不支持的图鉴类型", 422)
    if payload.entity_id:
        get_target(db, payload.entity_type, payload.entity_id)
    elif not payload.suggested:
        raise DomainError("SUGGESTION_REQUIRED", "缺失内容反馈需要填写建议资料", 422)
    from app.modules.catalog.contributions import normalize_suggestion

    suggestion, context = normalize_suggestion(
        db, payload.entity_type, payload.entity_id, payload.suggested
    )
    row = CatalogRecord(
        kind="reviews",
        entity_type=payload.entity_type,
        entity_id=payload.entity_id,
        status="PENDING",
        data={
            **payload.model_dump(),
            "suggested": suggestion,
            "context": context,
            "contributor": actor.id,
        },
    )
    db.add(row)
    db.commit()
    return success({"id": row.id, "status": row.status})


class BulkEdit(BaseModel):
    ids: list[str] = Field(min_length=1, max_length=100)
    changes: dict = Field(default_factory=dict)
    expected: dict[str, str] = Field(default_factory=dict)
    preview: bool = True


class MergeCards(BaseModel):
    source_id: str
    target_id: str
    preview: bool = True
    expected: dict[str, str] = Field(default_factory=dict)


def replace_reference(value, source_id, target_id):
    if isinstance(value, dict):
        result = {}
        for key, child in value.items():
            new_key = target_id if key == source_id else key
            replacement = replace_reference(child, source_id, target_id)
            if (
                new_key in result
                and isinstance(result[new_key], int)
                and isinstance(replacement, int)
            ):
                result[new_key] += replacement
            else:
                result[new_key] = replacement
        return result
    if isinstance(value, list):
        result = [replace_reference(v, source_id, target_id) for v in value]
        return list(dict.fromkeys(result)) if all(isinstance(v, str) for v in result) else result
    return target_id if value == source_id else value


@router.post("/cards/merge")
def merge_cards(
    payload: MergeCards, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    from app.admin_models import ContentMetadata
    from app.album_models import AlbumPage, AlbumSlot
    from app.future_models import (
        NotificationInboxItem,
    )
    from app.models import (
        AlbumCard,
        CardAlbum,
        DailyCardDraw,
        DetectedCard,
        Report,
        ScanCandidate,
        ScanFeedback,
        SocialPost,
        UserCollectionItem,
        UserWishlistItem,
    )

    from .catalog_service import _contains_reference, admin_card, audit, deletion_blockers, permit

    permit(actor, "catalog", "merge")
    source = get_target(db, "cards", payload.source_id)
    target = get_target(db, "cards", payload.target_id)
    if (
        source.id == target.id
        or target.status not in {"PUBLISHED", "OFFLINE"}
        or source.status in {"PENDING", "ARCHIVED"}
    ):
        raise DomainError(
            "INVALID_MERGE",
            "主记录须为已发布或下架小卡，重复记录不能是审核中或归档；不能合并自身",
            409,
        )
    before_source, before_target = admin_card(db, source), admin_card(db, target)
    blockers = deletion_blockers(db, "cards", source.id, False)
    # Phase 2 community records require domain-specific moderation semantics.
    if any(b["label"] in {"社区内容", "社区审核"} for b in blockers):
        raise DomainError("MERGE_DOMAIN_CONFLICT", "有关联社区记录，需先处理社区关系再合并", 409)
    if payload.preview:
        return success(
            {
                "source": before_source,
                "target": before_target,
                "relations": blockers,
                "expected": {
                    source.id: before_source["updated_at"],
                    target.id: before_target["updated_at"],
                },
            }
        )
    if (
        payload.expected.get(source.id) != before_source["updated_at"]
        or payload.expected.get(target.id) != before_target["updated_at"]
    ):
        raise DomainError("EDIT_CONFLICT", "记录已变化，请重新预览合并", 409)
    for model, owner_key in [
        (UserCollectionItem, "user_id"),
        (UserWishlistItem, "user_id"),
        (AlbumCard, "album_id"),
        (ScanCandidate, "detected_card_id"),
    ]:
        for relation in db.scalars(select(model).where(model.card_id == source.id)).all():
            existing = db.scalar(
                select(model).where(
                    model.card_id == target.id,
                    getattr(model, owner_key) == getattr(relation, owner_key),
                )
            )
            if existing:
                if model is UserCollectionItem:
                    existing.quantity += relation.quantity
                if model is ScanCandidate:
                    existing.similarity = max(existing.similarity, relation.similarity)
                    existing.rank = min(existing.rank, relation.rank)
                db.delete(relation)
            else:
                relation.card_id = target.id
    for relation in db.scalars(
        select(DailyCardDraw).where(DailyCardDraw.card_id == source.id)
    ).all():
        relation.card_id = target.id
    affected_books = set()
    # Never collapse intentional duplicate placements when merging official cards.
    for placement in db.scalars(select(AlbumSlot).where(AlbumSlot.card_id == source.id)):
        placement.card_id = target.id
        affected_books.add(db.get(AlbumPage, placement.page_id).album_id)
    for book in db.scalars(select(CardAlbum)):
        changed = book.id in affected_books
        for field in ("cover_config", "published_snapshot"):
            value = getattr(book, field)
            if _contains_reference(value, source.id):
                setattr(book, field, replace_reference(value, source.id, target.id))
                changed = True
        if changed:
            book.revision += 1
    for relation in db.scalars(
        select(DetectedCard).where(DetectedCard.user_confirmed_card_id == source.id)
    ).all():
        relation.user_confirmed_card_id = target.id
    for relation in db.scalars(select(Report).where(Report.target_id == source.id)).all():
        relation.target_id = target.id
    for model, field in [
        (ContentMetadata, "data"),
        (CatalogRecord, "data"),
        (SocialPost, "relation"),
        (ScanFeedback, "payload"),
        (NotificationInboxItem, "payload"),
    ]:
        for row in db.scalars(select(model)).all():
            value = getattr(row, field)
            if model is CatalogRecord and row.kind in {
                "import_input",
                "memberships",
                "company_relations",
            }:
                continue
            if _contains_reference(value, source.id):
                setattr(row, field, replace_reference(value, source.id, target.id))
    for relation in db.scalars(
        select(NotificationInboxItem).where(NotificationInboxItem.source_id == source.id)
    ).all():
        relation.source_id = target.id
    source.status = "ARCHIVED"
    source.admin_data = {
        **source.admin_data,
        "merged_into": target.id,
        "ever_published": source.admin_data.get("ever_published")
        or before_source["status"] == "PUBLISHED",
    }
    audit(
        db,
        actor,
        "catalog.card.merge",
        "card",
        source.id,
        before_source,
        {"merged_into": target.id, "relations": blockers},
    )
    db.commit()
    return success({"merged_into": target.id, "source_archived": True})


@router.get("/catalog-dashboard")
def catalog_dashboard(actor: User = Depends(current_admin), db: Session = Depends(get_db)):
    from datetime import UTC, datetime
    from zoneinfo import ZoneInfo

    from app.admin_models import AdminImportTask
    from app.models import ScanFeedback

    from .catalog_service import all_entities, permit, row_data

    permit(actor, "catalog")
    entities = all_entities(db)
    cards = db.scalars(select(Card)).all()
    today = datetime.now(ZoneInfo("Asia/Shanghai")).date()

    def is_today(value):
        timestamp = datetime.fromisoformat(value) if isinstance(value, str) else value
        return (
            timestamp.replace(tzinfo=timestamp.tzinfo or UTC)
            .astimezone(ZoneInfo("Asia/Shanghai"))
            .date()
            == today
        )

    counts = {kind: len(rows) for kind, rows in entities.items()}
    changes = {
        kind: sum(is_today(r["created_at"]) for r in rows) for kind, rows in entities.items()
    }
    changes["cards"] = sum(is_today(c.created_at) for c in cards)
    counts["entities"] = sum(counts[k] for k in ["albums", "events", "others"])
    for status in ["DRAFT", "PENDING", "PUBLISHED", "OFFLINE", "ARCHIVED"]:
        counts[status] = sum(c.status == status for c in cards)
    counts["import_errors"] = len(
        db.scalars(select(AdminImportTask).where(AdminImportTask.status == "HAS_ERRORS")).all()
    )
    counts["scan_unknown"] = len(
        db.scalars(select(ScanFeedback).where(ScanFeedback.status == "pending")).all()
    )
    counts["contributions"] = len(
        db.scalars(
            select(CatalogRecord).where(
                CatalogRecord.kind == "reviews", CatalogRecord.status == "PENDING"
            )
        ).all()
    )
    recent = db.scalars(
        select(OperationLog)
        .where(OperationLog.action.like("catalog.%"))
        .order_by(OperationLog.created_at.desc())
        .limit(20)
    ).all()
    return success({"counts": counts, "today": changes, "recent": [row_data(r) for r in recent]})


@router.get("/deletion-check/{kind}/{item_id}")
def deletion_check(
    kind: str, item_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    from .catalog_service import (
        admin_card,
        deletion_blockers,
        entity_payload,
        permit,
        was_published,
    )

    permit(actor, "catalog", "delete")
    row = get_target(db, kind, item_id)
    data = admin_card(db, row) if kind == "cards" else entity_payload(db, kind, row)
    strict = data["status"] == "ARCHIVED" or was_published(db, kind, item_id, data)
    blockers = deletion_blockers(db, kind, item_id, strict)
    return success(
        {
            "status": data["status"],
            "ever_published": strict,
            "blockers": blockers,
            "allowed": data["status"] in {"DRAFT", "OFFLINE", "ARCHIVED"} and not blockers,
        }
    )


@router.post("/detach/{kind}/{item_id}")
def detach(
    kind: str, item_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    from .catalog_service import (
        _raise_delete_blocked,
        audit,
        deletion_blockers,
        meta_for,
        permit,
        row_data,
    )

    permit(actor, "catalog", "delete")
    row = get_target(db, kind, item_id)
    meta = meta_for(db, kind, item_id) if kind != "cards" else None
    status = row.status if kind == "cards" else meta.status if meta else "PUBLISHED"
    if status not in {"OFFLINE", "ARCHIVED"}:
        raise DomainError("DETACH_REQUIRES_OFFLINE", "仅下架或归档记录可解除归属", 409)
    if kind in {"groups", "idols"}:
        raise DomainError("HISTORY_PROTECTED", "成员历史关系不能通过删除准备操作清除", 409)
    _raise_delete_blocked(deletion_blockers(db, kind, item_id, False))
    before = row_data(row)
    row.group_id = None
    if kind == "cards":
        row.idol_id = None
        row.source = ""
        row.admin_data = {
            **row.admin_data,
            "source_entity_id": "",
            "entity_version_id": None,
            "batch_id": None,
            "detached_for_delete": True,
        }
    else:
        if hasattr(row, "parent_event_id"):
            row.parent_event_id = None
        if meta:
            meta.data = {
                **meta.data,
                "group_id": "",
                "idol_id": None,
                "artists": [],
                "album_id": None,
                "parent_event_id": None,
                "detached_for_delete": True,
            }
    from sqlalchemy import delete

    from app.modules.catalog.tags import TAG_TYPES
    from app.modules.catalog.taxonomy_models import CatalogTagBinding

    if kind in TAG_TYPES:
        db.execute(
            delete(CatalogTagBinding).where(
                CatalogTagBinding.entity_type == TAG_TYPES[kind],
                CatalogTagBinding.entity_id == item_id,
            )
        )
        if kind == "cards":
            row.admin_data = {**row.admin_data, "tags": []}
        elif meta:
            meta.data = {**meta.data, "tags": []}
    for record in records(db, "sources", item_id):
        db.delete(record)
    audit(db, actor, "catalog.detach_for_delete", kind, item_id, before, row_data(row))
    db.commit()
    return success({"detached": True})


class ImportEdits(BaseModel):
    edits: list[dict] = Field(default_factory=list, max_length=2000)
    skip_rows: list[int] = Field(default_factory=list, max_length=2000)


@router.post("/imports/{task_id}/edit-preview")
def edit_import(
    task_id: str,
    payload: ImportEdits,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    from app.admin_models import AdminImportTask

    from .catalog_service import audit, permit, row_data
    from .import_service import validate_rows

    permit(actor, "catalog", "edit")
    task = db.get(AdminImportTask, task_id)
    source = next(iter(records(db, "import_input", task_id)), None)
    if not task or not source:
        raise DomainError("IMPORT_SOURCE_UNAVAILABLE", "历史任务不含原始预览，请重新上传文件", 409)
    if task.status == "COMPLETED":
        raise DomainError("IMPORT_COMPLETED", "已完成的任务不能修改", 409)
    rows = [dict(r) for r in source.data["rows"]]
    for edit in payload.edits:
        number = edit.get("row", 0)
        if (
            not isinstance(number, int)
            or number < 2
            or number > len(rows) + 1
            or not isinstance(edit.get("data"), dict)
        ):
            raise DomainError("INVALID_ROW", "行号或修改数据无效", 422)
        if set(edit["data"]) - set(rows[number - 2]):
            raise DomainError("INVALID_FIELD", "不能新增模板以外的字段", 422)
        rows[number - 2].update(edit["data"])
    if any(n < 2 or n > len(rows) + 1 for n in payload.skip_rows):
        raise DomainError("INVALID_ROW", "跳过行号无效", 422)
    valid, errors = validate_rows(db, task.kind, rows)
    task.rows = [r for r in valid if r["row"] not in payload.skip_rows]
    task.errors = [r for r in errors if r["row"] not in payload.skip_rows]
    task.status = "HAS_ERRORS" if task.errors else "VALIDATED"
    source.data = {"rows": rows, "skipped_rows": payload.skip_rows}
    audit(
        db,
        actor,
        "catalog.import.edit_preview",
        "import",
        task_id,
        None,
        {"edited_rows": [e["row"] for e in payload.edits], "skipped_rows": payload.skip_rows},
    )
    db.commit()
    return success(row_data(task))


def review_queue(actor: User = Depends(current_admin), db: Session = Depends(get_db)):
    from app.models import DetectedCard, Report, ScanCandidate, ScanFeedback

    from .catalog_service import permit, row_data

    permit(actor, "catalog")
    rows = [dict(row_data(r), queue="contribution") for r in records(db, "reviews")]
    for feedback in db.scalars(select(ScanFeedback)).all():
        detected = db.get(DetectedCard, feedback.detected_card_id)
        candidates = db.scalars(
            select(ScanCandidate).where(ScanCandidate.detected_card_id == feedback.detected_card_id)
        ).all()
        rows.append(
            {
                "id": feedback.id,
                "queue": "scan",
                "status": feedback.status,
                "entity_id": feedback.detected_card_id,
                "data": {
                    "reason": feedback.notes,
                    "suggested": feedback.payload,
                    "image_url": detected.crop_image_url if detected else "",
                    "candidates": [
                        {"card_id": c.card_id, "similarity": c.similarity} for c in candidates
                    ],
                },
            }
        )
    for report in db.scalars(select(Report)).all():
        if report.target_type.upper() in {"CARD", "IDOL", "ALBUM", "GROUP", "EVENT"}:
            rows.append(
                {
                    **row_data(report),
                    "queue": "report",
                    "entity_id": report.target_id,
                    "data": row_data(report),
                }
            )
    return success({"items": rows})


class ReviewAction(BaseModel):
    action: str
    reason: str = ""
    card_id: str | None = None
    changes: dict = Field(default_factory=dict)


def review_action(
    queue: str,
    item_id: str,
    payload: ReviewAction,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    from app.models import DetectedCard, Report, ScanFeedback

    from .catalog_service import (
        admin_card,
        audit,
        entity_payload,
        permit,
        save_card,
        save_entity,
        transition_card,
        transition_entity,
    )
    from .console_schemas import CardDraft, EntityDraft

    permit(actor, "catalog", "publish")
    if payload.action not in {"accept", "reject", "ignore", "match", "edit_accept"}:
        raise DomainError("INVALID_ACTION", "审核操作无效", 422)
    if (
        queue in {"scan", "contribution"}
        and payload.action in {"reject", "ignore"}
        and not payload.reason.strip()
    ):
        raise DomainError("REASON_REQUIRED", "请填写面向用户的未采纳原因", 422)
    if queue == "scan":
        row = db.get(ScanFeedback, item_id)
        if not row:
            raise DomainError("NOT_FOUND", "反馈不存在", 404)
        before = {"status": row.status, "payload": row.payload}
        if row.status not in {"pending", "reviewing"}:
            raise DomainError("REVIEW_COMPLETED", "反馈已处理", 409)
        if payload.action == "match":
            card = get_target(db, "cards", payload.card_id)
            if card.status not in {"PUBLISHED", "OFFLINE"}:
                raise DomainError("CARD_UNAVAILABLE", "只能匹配已发布或下架小卡", 422)
            detected = db.get(DetectedCard, row.detected_card_id)
            if not detected:
                raise DomainError("NOT_FOUND", "扫描对象不存在", 404)
            if detected.owned_added_at and detected.user_confirmed_card_id != card.id:
                raise DomainError("SCAN_ALREADY_ADDED", "此对象已加入收藏，不能改写收藏身份", 409)
            detected.user_confirmed_card_id = card.id
            row.payload = {
                **row.payload,
                "matched_card_id": card.id,
                "review_reason": payload.reason,
            }
        elif payload.action not in {"ignore", "reject"}:
            raise DomainError("MATCH_REQUIRED", "请选择匹配已有小卡、忽略或驳回", 422)
        row.payload = {**row.payload, "review_reason": payload.reason}
        row.status = (
            "resolved"
            if payload.action == "match"
            else "rejected"
            if payload.action == "reject"
            else "ignored"
        )
    elif queue == "report":
        row = db.get(Report, item_id)
        if not row:
            raise DomainError("NOT_FOUND", "举报不存在", 404)
        if row.status not in {"pending", "reviewing"}:
            raise DomainError("REVIEW_COMPLETED", "举报已处理", 409)
        if payload.action not in {"accept", "reject", "ignore"}:
            raise DomainError("INVALID_ACTION", "举报仅支持接受、驳回或忽略", 422)
        before = {"status": row.status}
        row.status = "resolved" if payload.action in {"accept", "edit_accept"} else "rejected"
    elif queue == "contribution":
        row = db.get(CatalogRecord, item_id)
        if not row or row.kind != "reviews":
            raise DomainError("NOT_FOUND", "贡献不存在", 404)
        if row.status != "PENDING":
            raise DomainError("REVIEW_COMPLETED", "贡献已处理", 409)
        before = {"status": row.status, "data": row.data}
        if payload.action in {"accept", "edit_accept"}:
            changes = dict(payload.changes or row.data.get("suggested", {}))
            if row.data.get("context", {}).get("append_versions") and "versions" in changes:
                from app.models import CatalogAlbum

                from .album_versions import album_names

                album = db.get(CatalogAlbum, row.entity_id)
                from app.modules.catalog.tags import entity_tags

                changes["tags"] = list(
                    dict.fromkeys(
                        [*entity_tags(db, "albums", album.id)["tags"], *changes.get("tags", [])]
                    )
                )
                changes["versions"] = list(
                    dict.fromkeys([*album_names(db, album), *changes["versions"]])
                )
            allowed = (
                CardDraft.model_fields if row.entity_type == "cards" else EntityDraft.model_fields
            )
            if not changes or set(changes) - set(allowed):
                raise DomainError("INVALID_SUGGESTION", "修改字段无效，请编辑后接受", 422)
            target = get_target(db, row.entity_type, row.entity_id) if row.entity_id else None
            current = (
                (
                    admin_card(db, target)
                    if row.entity_type == "cards"
                    else entity_payload(db, row.entity_type, target)
                )
                if target
                else {"status": "DRAFT"}
            )
            published = current["status"] == "PUBLISHED"
            if current["status"] not in {"DRAFT", "REJECTED", "OFFLINE", "PUBLISHED"}:
                raise DomainError("REVIEW_CONFLICT", "目标正在审核或已归档，请先处理目标状态", 409)
            if published:
                if row.entity_type == "cards":
                    transition_card(db, actor, target.id, "offline")
                else:
                    transition_entity(db, actor, row.entity_type, target.id, "offline")
            if row.entity_type == "cards":
                saved = save_card(
                    db,
                    actor,
                    CardDraft.model_validate(
                        {**(admin_card(db, target) if target else {}), **changes}
                    ),
                    target.id if target else None,
                    tag_source="USER_SUBMITTED",
                    submission_id=row.id,
                )
                row.entity_id = saved.id
            else:
                saved = save_entity(
                    db,
                    actor,
                    row.entity_type,
                    EntityDraft.model_validate(
                        {
                            **(entity_payload(db, row.entity_type, target) if target else {}),
                            **changes,
                        }
                    ),
                    target.id if target else None,
                    tag_source="USER_SUBMITTED",
                    submission_id=row.id,
                )
                row.entity_id = saved["id"]
            # One approval publishes both the subject and its proposed tags atomically.
            if row.entity_type == "cards":
                transition_card(db, actor, row.entity_id, "submit")
                transition_card(db, actor, row.entity_id, "publish")
            else:
                transition_entity(db, actor, row.entity_type, row.entity_id, "submit")
                transition_entity(db, actor, row.entity_type, row.entity_id, "publish")
        row.status = "ACCEPTED" if payload.action in {"accept", "edit_accept"} else "REJECTED"
        row.data = {**row.data, "reviewer": actor.id, "review_reason": payload.reason}
    else:
        raise DomainError("INVALID_QUEUE", "队列不存在", 404)
    audit(
        db,
        actor,
        "catalog.review." + payload.action,
        queue,
        item_id,
        before,
        {"status": row.status},
    )
    db.commit()
    return success({"status": row.status})


@router.post("/cards/bulk-edit")
def bulk_edit(
    payload: BulkEdit, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    from .catalog_service import admin_card, fail_fields, permit, save_card, validate_relations
    from .console_schemas import CardDraft

    permit(actor, "catalog", "edit")
    allowed = {
        "group_id",
        "idol_id",
        "source_entity_id",
        "source_entity_type",
        "entity_version_id",
        "version",
        "edition",
        "card_type",
        "is_official",
        "is_limited",
        "tags",
        "add_tags",
        "remove_tags",
    }
    if set(payload.changes) - allowed:
        raise DomainError("INVALID_BULK_FIELDS", "不支持的批量字段", 422)
    updates = []
    for item_id in dict.fromkeys(payload.ids):
        row = get_target(db, "cards", item_id)
        before = admin_card(db, row)
        if row.status not in {"DRAFT", "REJECTED", "OFFLINE"}:
            raise DomainError("CARD_NOT_EDITABLE", "请先下架或驳回后批量编辑", 409)
        if not payload.preview and payload.expected.get(item_id) != before["updated_at"]:
            raise DomainError("EDIT_CONFLICT", "内容已变化，请重新预览", 409)
        changes = {k: v for k, v in payload.changes.items() if k in CardDraft.model_fields}
        data = {**before, **changes}
        if (
            data.get("source_entity_id") != before.get("source_entity_id")
            and "entity_version_id" not in changes
        ):
            data["entity_version_id"] = None
        if "add_tags" in payload.changes or "remove_tags" in payload.changes:
            data["tags"] = [
                t
                for t in dict.fromkeys(
                    [*(data.get("tags") or []), *payload.changes.get("add_tags", [])]
                )
                if t not in payload.changes.get("remove_tags", [])
            ]
        draft = CardDraft.model_validate(data)
        fail_fields(validate_relations(db, draft, existing_card=row))
        updates.append((row, before, draft))
    preview = [
        {
            "id": row.id,
            "before": before,
            "after": draft.model_dump(),
            "updated_at": before["updated_at"],
        }
        for row, before, draft in updates
    ]
    if not payload.preview:
        for row, _before, draft in updates:
            save_card(db, actor, draft, row.id)
        db.commit()
    return success({"items": preview, "applied": not payload.preview})


class GenerateBatch(BaseModel):
    member_ids: list[str] = Field(min_length=1, max_length=100)
    cards_per_member: int = Field(default=1, ge=1, le=10)


@router.post("/batches/{batch_id}/generate")
def generate_batch(
    batch_id: str,
    payload: GenerateBatch,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    from .catalog_service import audit, permit, row_data, save_card
    from .console_schemas import CardDraft

    permit(actor, "catalog", "edit")
    batch = db.get(CatalogRecord, batch_id)
    if not batch or batch.kind != "batches":
        raise DomainError("NOT_FOUND", "批次不存在", 404)
    if batch.data.get("card_ids") or batch.data.get("generated_at"):
        raise DomainError("BATCH_GENERATED", "该批次已生成，避免重复创建", 409)
    if len(set(payload.member_ids)) * payload.cards_per_member > 100:
        raise DomainError("BATCH_TOO_LARGE", "单批最多生成 100 张", 422)
    ids = []
    for member_id in dict.fromkeys(payload.member_ids):
        idol = db.get(Idol, member_id)
        if not idol:
            raise DomainError("IDOL_NOT_FOUND", "艺人不存在", 422)
        for number in range(1, payload.cards_per_member + 1):
            data = {
                **batch.data,
                "title": f"{idol.name} {batch.data['name']} {number:02d}",
                "idol_id": member_id,
                "batch_id": batch_id,
                "card_number": str(number),
            }
            ids.append(save_card(db, actor, CardDraft.model_validate(data)).id)
    before = row_data(batch)
    from datetime import UTC, datetime

    batch.data = {**batch.data, "card_ids": ids, "generated_at": datetime.now(UTC).isoformat()}
    audit(db, actor, "catalog.batch.generate", "batch", batch_id, before, row_data(batch))
    db.commit()
    return success({"ids": ids})


class RemoveBatchCard(BaseModel):
    card_id: str


@router.post("/batches/{batch_id}/remove-card")
def remove_batch_card(
    batch_id: str,
    payload: RemoveBatchCard,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    from .catalog_service import audit, permit

    permit(actor, "catalog", "edit")
    batch = db.get(CatalogRecord, batch_id)
    card = get_target(db, "cards", payload.card_id)
    if not batch or batch.kind != "batches":
        raise DomainError("NOT_FOUND", "批次不存在", 404)
    if card.status not in {"DRAFT", "REJECTED", "OFFLINE", "ARCHIVED"}:
        raise DomainError("CARD_NOT_EDITABLE", "请先下架或驳回小卡再解除批次关系", 409)
    if (
        card.id not in batch.data.get("card_ids", [])
        and card.admin_data.get("batch_id") != batch_id
    ):
        raise DomainError("NOT_IN_BATCH", "小卡不属于该批次", 409)
    before = dict(batch.data)
    batch.data = {
        **batch.data,
        "card_ids": [item_id for item_id in batch.data.get("card_ids", []) if item_id != card.id],
    }
    if card.admin_data.get("batch_id") == batch_id:
        card.admin_data = {**card.admin_data, "batch_id": None}
    audit(db, actor, "catalog.batch.remove_card", "batches", batch_id, before, batch.data)
    db.commit()
    return success({"removed": True})


@router.post("/batches/{batch_id}/validate")
@router.post("/batches/{batch_id}/publish-ready")
def validate_batch(
    batch_id: str,
    request: Request,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    from .catalog_service import admin_card, permit, transition_card, validate_relations
    from .console_schemas import CardDraft

    publish = request.url.path.endswith("publish-ready")
    permit(actor, "catalog", "publish" if publish else "view")
    batch = db.get(CatalogRecord, batch_id)
    if not batch or batch.kind != "batches":
        raise DomainError("NOT_FOUND", "批次不存在", 404)
    results = []
    for row in db.scalars(select(Card)).all():
        if (row.admin_data or {}).get("batch_id") != batch_id and row.id not in batch.data.get(
            "card_ids", []
        ):
            continue
        errors = validate_relations(db, CardDraft.model_validate(admin_card(db, row)), True, row)
        if publish and not errors and row.status in {"DRAFT", "OFFLINE", "REJECTED", "PENDING"}:
            if row.status != "PENDING":
                transition_card(db, actor, row.id, "submit")
            transition_card(db, actor, row.id, "publish")
        results.append({"id": row.id, "title": row.title, "status": row.status, "errors": errors})
    db.commit()
    return success({"items": results})


def quality(actor: User = Depends(current_admin), db: Session = Depends(get_db)):
    from .catalog_service import admin_card, all_entities, validate_relations
    from .console_schemas import CardDraft

    rows = []
    for card in db.scalars(select(Card).where(Card.status != "ARCHIVED")).all():
        issues = validate_relations(db, CardDraft.model_validate(admin_card(db, card)), True, card)
        if issues:
            rows.append({"id": card.id, "kind": "cards", "name": card.title, "issues": issues})
    for kind, entities in all_entities(db).items():
        if kind in {"groups", "idols"}:
            rows += [
                {
                    "id": e["id"],
                    "kind": kind,
                    "name": e["name"],
                    "issues": [{"field": "image_url", "message": "缺少头像 / 主图"}],
                }
                for e in entities
                if not e.get("image_url") and e["status"] != "ARCHIVED"
            ]
    return success({"items": rows})


@router.get("/scan-index")
def scan_index(actor: User = Depends(current_admin), db: Session = Depends(get_db)):
    from datetime import UTC, datetime

    from app.future_models import OutboxEvent
    from app.integrations.card_matcher.adapter import CardMatcherAdapter

    from .catalog_service import permit

    permit(actor, "catalog")
    cards = db.scalars(select(Card)).all()
    indexed = {
        r["card_id"] for r in CardMatcherAdapter().indexed({c.id: c.image_url for c in cards})
    }
    events = db.scalars(
        select(OutboxEvent)
        .where(OutboxEvent.event_type == "catalog.card.image.updated")
        .order_by(OutboxEvent.occurred_at.desc())
    ).all()
    rows = []
    for card in cards:
        event = next(
            (
                e
                for e in events
                if e.aggregate_id == card.id and e.payload.get("image_url") == card.image_url
            ),
            None,
        )
        status = (
            "Disabled"
            if not card.image_url or card.status == "ARCHIVED"
            else "Indexed"
            if card.id in indexed
            else "Failed"
            if event and event.last_error
            else "Processing"
            if event
            and event.payload.get("processing_started_at")
            and not event.payload.get("processing_finished_at")
            and (
                datetime.now(UTC) - datetime.fromisoformat(event.payload["processing_started_at"])
            ).total_seconds()
            < 300
            else "Pending"
        )
        rows.append(
            {
                "id": card.id,
                "title": card.title,
                "status": status,
                "failure_reason": event.last_error if event else "",
                "attempts": event.publish_attempts if event else 0,
            }
        )
    return success({"items": rows})


@router.post("/scan-index/{card_id}/retry")
def retry_index(card_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)):
    from app.common.events import enqueue_outbox

    from .catalog_service import audit, permit

    permit(actor, "catalog", "edit")
    card = get_target(db, "cards", card_id)
    if not card.image_url or card.status == "ARCHIVED":
        raise DomainError("IMAGE_REQUIRED", "缺少图片或记录已归档", 422)
    enqueue_outbox(
        db,
        event_type="catalog.card.image.updated",
        aggregate_type="card",
        aggregate_id=card_id,
        payload={"card_id": card_id, "image_url": card.image_url},
    )
    audit(db, actor, "catalog.index.retry", "card", card_id, None, {"status": "Pending"})
    db.commit()
    return success({"queued": True})


def records(db, kind, entity_id=None):
    query = select(CatalogRecord).where(CatalogRecord.kind == kind)
    if entity_id:
        query = query.where(CatalogRecord.entity_id == entity_id)
    return db.scalars(query.order_by(CatalogRecord.updated_at.desc())).all()


def actor_names(db, kind, row):
    from .catalog_service import meta_for

    meta = meta_for(db, kind, row.id)
    data = meta.data if meta else {}
    return data.get("artists") or ([{"type": "groups", "id": row.group_id}] if row.group_id else [])


def get_target(db, kind, item_id):
    from .catalog_service import entity

    if kind == "cards":
        row = db.get(Card, item_id)
        if not row:
            raise DomainError("NOT_FOUND", "小卡不存在", 404)
        return row
    return entity(db, kind, item_id)


def validate_record(db, kind, payload):
    if kind not in {
        "versions",
        "sources",
        "batches",
        "companies",
        "company_relations",
        "memberships",
    }:
        raise DomainError("INVALID_KIND", "不支持的记录类型", 422)
    data = payload.data
    if kind == "companies" and "enabled" in data and not isinstance(data["enabled"], bool):
        raise DomainError("INVALID_COMPANY", "公司开启状态必须为是或否", 422)
    if payload.status != "DRAFT":
        raise DomainError("INVALID_STATUS", "状态必须通过审核操作维护", 422)
    if kind in {"versions", "sources", "company_relations"}:
        get_target(db, payload.entity_type, payload.entity_id)
    if kind in {"versions", "companies", "batches"} and not str(data.get("name", "")).strip():
        raise DomainError("NAME_REQUIRED", "请填写名称", 422)
    if kind == "sources":
        get_target(db, data.get("type"), data.get("id"))
        if data.get("id") == payload.entity_id:
            raise DomainError("SOURCE_CYCLE", "来源不能指向自身", 422)
        pending = [data["id"]]
        seen = set()
        edges = records(db, "sources")
        while pending:
            target = pending.pop()
            if target == payload.entity_id:
                raise DomainError("SOURCE_CYCLE", "来源链不能形成循环", 422)
            if target in seen:
                continue
            seen.add(target)
            pending += [e.data["id"] for e in edges if e.entity_id == target]
    if kind == "company_relations":
        company = db.get(CatalogRecord, data.get("company_id"))
        if not company or company.kind != "companies":
            raise DomainError("COMPANY_NOT_FOUND", "公司不存在", 422)
    if kind == "memberships":
        if not db.get(Idol, payload.entity_id) or not db.get(Group, data.get("group_id")):
            raise DomainError("INVALID_MEMBERSHIP", "请选择有效艺人和组合", 422)
        if data.get("status", "active") not in {"active", "inactive", "former"}:
            raise DomainError("INVALID_STATUS", "成员状态无效", 422)
        if not data.get("start_date"):
            raise DomainError("START_DATE_REQUIRED", "成员经历需要明确填写开始日期", 422)
        if data.get("status", "active") in {"active", "inactive"} and data.get("end_date"):
            raise DomainError("INVALID_MEMBERSHIP", "活动中或暂停成员不能填写退出日期", 422)
    for field in ("start_date", "end_date", "release_date"):
        if data.get(field):
            try:
                date.fromisoformat(data[field])
            except ValueError as exc:
                raise DomainError("INVALID_DATE", "日期必须为 YYYY-MM-DD", 422) from exc
    if data.get("start_date") and data.get("end_date") and data["end_date"] < data["start_date"]:
        raise DomainError("INVALID_DATE_RANGE", "结束日期不能早于开始日期", 422)


def company_relation_counts(company_id: str, relations: list[CatalogRecord]) -> dict:
    from .catalog_companies import relation_is_active

    current = {"groups": set(), "idols": set()}
    history = {"groups": set(), "idols": set()}
    for relation in relations:
        if relation.data.get("company_id") != company_id or relation.entity_type not in current:
            continue
        bucket = current if relation_is_active(relation) else history
        bucket[relation.entity_type].add(relation.entity_id)
    return {
        "group_count": len(current["groups"]),
        "idol_count": len(current["idols"]),
        "group_history_count": len(history["groups"]),
        "idol_history_count": len(history["idols"]),
    }


def company_relation_items(db: Session, company_id: str) -> dict[str, list[dict]]:
    from .catalog_companies import relation_is_active
    from .catalog_service import entity_payload

    result = {"groups": [], "idols": []}
    company_relations = [
        relation
        for relation in records(db, "company_relations")
        if relation.data.get("company_id") == company_id and relation.entity_type in result
    ]
    for relation in company_relations:
        model = Group if relation.entity_type == "groups" else Idol
        entity = db.get(model, relation.entity_id)
        if not entity:
            continue
        payload = entity_payload(db, relation.entity_type, entity)
        item = {
            "relation_id": relation.id,
            "entity_id": entity.id,
            "name": payload.get("name", entity.name),
            "status": payload.get("status", "PUBLISHED"),
            "relation_status": "current" if relation_is_active(relation) else "history",
            "relation_type": relation.data.get("relation_type", "Agency"),
            "start_date": relation.data.get("start_date", ""),
            "end_date": relation.data.get("end_date", ""),
            "date_unknown": bool(relation.data.get("date_unknown")),
            "source": relation.data.get("source", ""),
        }
        if relation.entity_type == "idols":
            memberships = db.scalars(
                select(GroupMembership).where(GroupMembership.idol_id == entity.id)
            ).all()
            item["groups"] = [
                {"id": group.id, "name": group.name}
                for membership in memberships
                if membership.status in {"active", "inactive"}
                and (group := db.get(Group, membership.group_id))
            ]
        result[relation.entity_type].append(item)
    for items in result.values():
        items.sort(
            key=lambda item: (
                item["relation_status"] != "current",
                item["name"].casefold(),
                item["relation_id"],
            )
        )
    return result


@router.get("/records/{kind}")
def list_records(
    kind: str,
    entity_id: str | None = None,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    from .catalog_service import permit, row_data

    permit(actor, "catalog")
    if kind == "reviews":
        raise DomainError("NOT_FOUND", "旧审核队列已停用", 404)
    rows = records(db, kind, entity_id)
    items = [row_data(r) for r in rows]
    if kind == "companies":
        from .catalog_companies import company_enabled

        relations = records(db, "company_relations")
        items = [
            {
                **item,
                "data": {**item["data"], "enabled": company_enabled(row)},
                **company_relation_counts(item["id"], relations),
            }
            for item, row in zip(items, rows, strict=True)
        ]
    if kind == "memberships" and entity_id:
        from .catalog_memberships import membership_date_info

        memberships = db.scalars(
            select(GroupMembership).where(GroupMembership.idol_id == entity_id)
        ).all()
        date_info = membership_date_info(db, memberships)
        known = {r["data"].get("membership_id") for r in items}
        items += [
            {
                "id": "legacy-" + m.id,
                "kind": kind,
                "entity_type": "idols",
                "entity_id": entity_id,
                "status": "DRAFT",
                "data": {**row_data(m), **date_info[m.id], "membership_id": m.id},
            }
            for m in memberships
            if m.id not in known
        ]
    return success({"items": items})


@router.get("/records/companies/{company_id}/detail")
def company_detail(
    company_id: str,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    from .catalog_service import permit, row_data

    permit(actor, "catalog")
    company = db.get(CatalogRecord, company_id)
    if not company or company.kind != "companies":
        raise DomainError("NOT_FOUND", "公司不存在", 404)
    relations = records(db, "company_relations")
    linked = company_relation_items(db, company_id)
    return success(
        {
            "company": {
                **row_data(company),
                **company_relation_counts(company_id, relations),
            },
            "groups": linked["groups"],
            "idols": linked["idols"],
        }
    )


@router.post("/records/{kind}")
@router.put("/records/{kind}/{record_id}")
def save_record(
    kind: str,
    payload: RecordDraft,
    record_id: str | None = None,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    from .catalog_service import audit, permit, row_data

    permit(actor, "catalog", "edit")
    validate_record(db, kind, payload)
    row = db.get(CatalogRecord, record_id) if record_id else None
    if record_id and (not row or row.kind != kind):
        raise DomainError("NOT_FOUND", "记录不存在", 404)
    before = row_data(row) if row else None
    from .catalog_companies import company_enabled

    if kind == "company_relations":
        company = db.get(CatalogRecord, payload.data.get("company_id"))
        if not company_enabled(company) and (not row or row.data.get("company_id") != company.id):
            raise DomainError("COMPANY_DISABLED", "公司未开启，不能新增关联", 422)
    # Legacy relation/company maintenance must use the same public revision chain.
    from app.modules.catalog import profiles

    affected = set()
    if kind in {"memberships", "company_relations"}:
        affected.add((payload.entity_type, payload.entity_id))
        if kind == "memberships":
            affected.add(("groups", payload.data.get("group_id")))
    elif kind == "companies" and row and payload.data.get("name") != row.data.get("name"):
        affected.update(
            (r.entity_type, r.entity_id)
            for r in records(db, "company_relations")
            if r.data.get("company_id") == row.id and r.status != "ARCHIVED"
        )
    profile_before = {}
    for target in sorted(affected):
        if target[0] not in {"groups", "idols"}:
            continue
        try:
            value = profiles.snapshot(db, *target)
        except DomainError as error:
            if error.status_code == 404:
                continue
            raise
        permit(actor, "catalog", "publish")
        profiles.initialize(db, *target)
        profile_before[target] = value
    if kind == "memberships" and profile_before and payload.data.get("membership_id"):
        data = payload.data
        from app.models import Card

        for card in db.scalars(
            select(Card).where(
                Card.idol_id == payload.entity_id,
                Card.group_id == data["group_id"],
                Card.status != "ARCHIVED",
            )
        ):
            if card.release_date and (
                card.release_date < data["start_date"]
                or data.get("end_date")
                and card.release_date > data["end_date"]
            ):
                raise DomainError(
                    "HISTORY_PROTECTED", "修改后的有效期不能排除已关联小卡的发行日期", 409
                )
    if kind == "versions" and payload.entity_type == "albums":
        from .album_versions import validate_record_name

        validate_record_name(db, payload, record_id)
    if kind == "companies":
        from .catalog_companies import company_name_key

        name = " ".join(str(payload.data["name"]).split())
        if any(
            c.id != record_id and company_name_key(c.data["name"]) == company_name_key(name)
            for c in records(db, "companies")
        ):
            raise DomainError("COMPANY_EXISTS", "公司名称已存在，请使用已有公司", 409)
        payload.data = {
            **payload.data,
            "name": name,
            "enabled": payload.data.get("enabled", company_enabled(row) if row else True),
        }
    if kind == "company_relations":
        payload.data = {**payload.data, "date_unknown": not bool(payload.data.get("start_date"))}
    if row and (row.entity_type != payload.entity_type or row.entity_id != payload.entity_id):
        raise DomainError("RELATION_OWNER_IMMUTABLE", "已有记录不能改换所属实体", 409)
    if row and kind == "versions":
        protected = {
            key: value
            for key, value in row.data.items()
            if key in {"normalization", "original_album_id", "original_name", "original_snapshot"}
        }
        payload.data = {**payload.data, **protected}
    if row and kind == "batches" and row.data.get("card_ids") and row.data != payload.data:
        raise DomainError("BATCH_GENERATED", "已生成批次的字段请通过批量编辑维护", 409)
    if not row:
        row = CatalogRecord(kind=kind)
        db.add(row)
    for key, value in payload.model_dump().items():
        if kind == "companies" and before and key == "status":
            continue  # Enabled is independent from the historical publication status.
        setattr(row, key, value)
    db.flush()
    if kind == "memberships":
        data = row.data
        membership = (
            db.get(GroupMembership, data.get("membership_id"))
            if data.get("membership_id")
            else None
        )
        if membership and membership.idol_id != payload.entity_id:
            raise DomainError("INVALID_MEMBERSHIP", "成员关系不属于该艺人", 422)
        start = date.fromisoformat(data["start_date"]) if data.get("start_date") else date.today()
        if not membership:
            membership = GroupMembership(
                idol_id=payload.entity_id, group_id=data["group_id"], start_date=start
            )
            db.add(membership)
        elif membership.group_id != data["group_id"]:
            raise DomainError("HISTORY_IMMUTABLE", "历史关系不能改换组合，请新增一段关系", 409)
        membership.status = data.get("status", "active")
        membership.start_date = start
        membership.end_date = date.fromisoformat(data["end_date"]) if data.get("end_date") else None
        if membership.status == "former" and not membership.end_date:
            raise DomainError("END_DATE_REQUIRED", "退团需要填写退出日期", 422)
        db.flush()
        row.data = {**data, "membership_id": membership.id}
        if data.get("is_primary"):
            for other in records(db, "memberships", payload.entity_id):
                if other.id != row.id and other.data.get("is_primary"):
                    other.data = {**other.data, "is_primary": False}
    audit(db, actor, f"catalog.{kind}.save", kind, row.id, before, row_data(row))
    if kind == "versions" and row.entity_type == "albums":
        from .album_versions import sync_after_record

        sync_after_record(db, row.entity_id, before["data"]["name"] if before else None)
    if kind == "versions":
        from app.modules.catalog.media_import import queue_images

        queue_images(db, "versions", row.id, row.data)
    for target, previous in profile_before.items():
        profiles.append_version(
            db, *target, previous, profiles.snapshot(db, *target), summary="平台核实更新关联资料"
        )
    db.commit()
    return success(row_data(row))


@router.delete("/records/{kind}/{record_id}")
def delete_record(
    kind: str, record_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    from .catalog_service import _contains_reference, audit, permit, row_data

    permit(actor, "catalog", "delete")
    row = db.get(CatalogRecord, record_id)
    if not row or row.kind != kind:
        raise DomainError("NOT_FOUND", "记录不存在", 404)
    if kind in {"memberships", "company_relations", "reviews"}:
        raise DomainError("HISTORY_PROTECTED", "历史关系和审核记录不得删除", 409)
    if kind == "versions" and row.entity_type == "albums":
        from .album_versions import referenced

        if referenced(db, record_id):
            raise DomainError("ENTITY_HAS_RELATIONS", "版本仍有关联或历史映射，请先解除关联", 409)
    if any(
        _contains_reference(c.admin_data, record_id) for c in db.scalars(select(Card)).all()
    ) or any(
        r.id != record_id and _contains_reference(r.data, record_id)
        for r in db.scalars(select(CatalogRecord)).all()
    ):
        raise DomainError("ENTITY_HAS_RELATIONS", "仍有关联记录，请先解除关联", 409)
    audit(db, actor, f"catalog.{kind}.delete", kind, record_id, row_data(row), None)
    db.delete(row)
    if kind == "versions" and row.entity_type == "albums":
        from .album_versions import sync_after_record

        sync_after_record(db, row.entity_id, row.data["name"])
    db.commit()
    return success({"deleted": True})


@router.get("/entities/{kind}/{item_id}/detail")
def detail(
    kind: str, item_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    from app.admin_models import CardImageVersion
    from app.models import IdolOfficialAccount, SocialPost

    from .catalog_service import admin_card, all_entities, entity_payload, permit, row_data

    permit(actor, "catalog")
    row = get_target(db, kind, item_id)
    cards = db.scalars(select(Card)).all()
    related = [
        c
        for c in cards
        if c.id == item_id
        or c.group_id == item_id
        or c.idol_id == item_id
        or (c.admin_data or {}).get("source_entity_id") == item_id
    ]
    memberships = db.scalars(
        select(GroupMembership).where(
            (GroupMembership.idol_id == item_id) | (GroupMembership.group_id == item_id)
        )
    ).all()
    from .catalog_memberships import membership_date_info

    membership_dates = membership_date_info(db, memberships)
    history = db.scalars(
        select(OperationLog)
        .where(OperationLog.target_id == item_id)
        .order_by(OperationLog.created_at.desc())
    ).all()
    entities = all_entities(db)
    related_entities = [
        dict(r, entity_type=k)
        for k, rows in entities.items()
        if k not in {"groups", "idols"}
        for r in rows
        if r.get("group_id") == item_id
        or any(a.get("id") == item_id for a in r.get("artists", []))
        or r.get("idol_id") == item_id
        or r.get("parent_event_id") == item_id
        or r.get("album_id") == item_id
        or any(
            s.entity_id == r["id"] and s.data.get("id") == item_id for s in records(db, "sources")
        )
    ]
    return success(
        {
            "entity": admin_card(db, row) if kind == "cards" else entity_payload(db, kind, row),
            "cards": [admin_card(db, c) for c in related],
            "memberships": [{**row_data(m), **membership_dates[m.id]} for m in memberships],
            "entities": related_entities,
            "history": [row_data(h) for h in history],
            "assets": [
                row_data(a)
                for a in db.scalars(
                    select(CardImageVersion)
                    .where(CardImageVersion.card_id == item_id)
                    .order_by(CardImageVersion.created_at.desc())
                ).all()
            ]
            if kind == "cards"
            else [],
            "feedback": [row_data(r) for r in records(db, "reviews", item_id)],
            "scan": next(
                (r for r in scan_index(actor, db)["data"]["items"] if r["id"] == item_id), None
            )
            if kind == "cards"
            else None,
            "social": [
                row_data(p)
                for p in db.scalars(
                    select(SocialPost).where(
                        (SocialPost.group_id == item_id) | (SocialPost.idol_id == item_id)
                    )
                ).all()
            ],
            "accounts": [
                row_data(a)
                for a in db.scalars(
                    select(IdolOfficialAccount).where(
                        (IdolOfficialAccount.group_id == item_id)
                        | (IdolOfficialAccount.idol_id == item_id)
                    )
                ).all()
            ],
        }
    )
