import unicodedata
from typing import Literal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_admin
from app.models import User
from app.modules.admin.catalog_service import audit, permit

from .tags import TAG_TYPES, clean_name, ensure_tag, find_tag, tag_payload
from .taxonomy_models import CatalogTag, CatalogTagBinding

TagType = Literal["ALBUM", "EVENT", "OTHER", "CARD"]
router = APIRouter(tags=["Catalog Tags"])


class TagCreate(BaseModel):
    entity_type: TagType
    name: str = Field(min_length=1, max_length=160)


class TagUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    status: Literal["ACTIVE", "DISABLED"] = "ACTIVE"


def details(db, tag):
    return {
        **tag_payload(tag),
        "normalized_name": tag.normalized_name,
        "usage_count": db.scalar(
            select(func.count())
            .select_from(CatalogTagBinding)
            .where(CatalogTagBinding.tag_id == tag.id)
        ),
        "operator_id": tag.operator_id,
        "submission_id": tag.submission_id,
        "created_at": tag.created_at.isoformat(),
        "updated_at": tag.updated_at.isoformat(),
    }


@router.get("/catalog/tags")
def public_tags(
    entity_type: TagType, q: str = Query("", max_length=80), db: Session = Depends(get_db)
):
    rows = db.scalars(
        select(CatalogTag)
        .where(CatalogTag.entity_type == entity_type, CatalogTag.status == "ACTIVE")
        .order_by(CatalogTag.name)
    ).all()
    needle = " ".join(unicodedata.normalize("NFKC", q).split()).casefold()
    return success({"items": [tag_payload(t) for t in rows if needle in t.normalized_name]})


@router.get("/admin/console/tags")
def list_tags(
    entity_type: TagType | None = None,
    q: str = Query("", max_length=80),
    status: Literal["ACTIVE", "DISABLED"] | None = None,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "catalog")
    rows = db.scalars(select(CatalogTag).order_by(CatalogTag.updated_at.desc())).all()
    needle = " ".join(unicodedata.normalize("NFKC", q).split()).casefold()
    return success(
        {
            "items": [
                details(db, t)
                for t in rows
                if (not entity_type or t.entity_type == entity_type)
                and (not status or t.status == status)
                and needle in t.normalized_name
            ]
        }
    )


@router.post("/admin/console/tags")
def create_tag(
    payload: TagCreate, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    permit(actor, "catalog", "edit")
    name, key = clean_name(payload.name)
    tag = ensure_tag(db, payload.entity_type, name, key, operator_id=actor.id)
    if tag.status != "ACTIVE":
        raise DomainError("TAG_DISABLED", "同名标签已停用，请在列表中编辑启用", 409)
    audit(db, actor, "catalog.tag.create", "tags", tag.id, None, tag_payload(tag))
    db.commit()
    return success(details(db, tag))


@router.put("/admin/console/tags/{tag_id}")
def update_tag(
    tag_id: str,
    payload: TagUpdate,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "catalog", "edit")
    tag = db.get(CatalogTag, tag_id)
    if not tag:
        raise DomainError("NOT_FOUND", "标签不存在", 404)
    if payload.status != tag.status:
        permit(actor, "catalog", "offline")
    name, key = clean_name(payload.name)
    duplicate = find_tag(db, tag.entity_type, key)
    if duplicate and duplicate.id != tag.id:
        raise DomainError("TAG_DUPLICATE", "该实体类型下已有同名标签，请使用已有标签", 409)
    before = tag_payload(tag)
    tag.name, tag.normalized_name, tag.status = name, key, payload.status
    audit(db, actor, "catalog.tag.update", "tags", tag.id, before, tag_payload(tag))
    db.commit()
    return success(details(db, tag))


@router.get("/admin/console/tags/{tag_id}/contents")
def tag_contents(tag_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)):
    from app.models import Card
    from app.modules.admin.catalog_service import MODELS, admin_card, entity_payload

    permit(actor, "catalog")
    tag = db.get(CatalogTag, tag_id)
    if not tag:
        raise DomainError("NOT_FOUND", "标签不存在", 404)
    kind = next(k for k, value in TAG_TYPES.items() if value == tag.entity_type)
    rows = []
    for link in db.scalars(select(CatalogTagBinding).where(CatalogTagBinding.tag_id == tag.id)):
        item = db.get(Card if kind == "cards" else MODELS[kind], link.entity_id)
        if item:
            data = admin_card(db, item) if kind == "cards" else entity_payload(db, kind, item)
            rows.append(
                {
                    "id": item.id,
                    "kind": kind,
                    "name": data.get("title") or data.get("name"),
                    "status": data["status"],
                }
            )
    return success({"tag": details(db, tag), "items": rows})
