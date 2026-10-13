"""Shared normalization and transactional tag binding; no pending global tags."""

import unicodedata

from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError

from app.common.response import DomainError

from .taxonomy_models import CatalogTag, CatalogTagBinding

TAG_TYPES = {"albums": "ALBUM", "events": "EVENT", "others": "OTHER", "cards": "CARD"}


def clean_name(value):
    if not isinstance(value, str):
        raise DomainError("INVALID_TAG", "标签名称必须为文字", 422)
    display = " ".join(unicodedata.normalize("NFKC", value).split())
    if (
        not display
        or len(display) > 80
        or any(unicodedata.category(c).startswith("C") for c in display)
    ):
        raise DomainError("INVALID_TAG", "标签名称须为 1–80 字符，不能包含控制字符", 422)
    return display, display.casefold()


def normalized_names(values):
    if not isinstance(values, list) or len(values) > 30:
        raise DomainError("INVALID_TAG", "最多选择 30 个标签", 422)
    result = {}
    for value in values:
        display, key = clean_name(value)
        result.setdefault(key, display)
    return result


def find_tag(db, entity_type, key):
    return db.scalar(
        select(CatalogTag).where(
            CatalogTag.entity_type == entity_type, CatalogTag.normalized_name == key
        )
    )


def existing_tags(db, entity_type, entity_id):
    return list(
        db.scalars(
            select(CatalogTag)
            .join(CatalogTagBinding, CatalogTagBinding.tag_id == CatalogTag.id)
            .where(
                CatalogTagBinding.entity_type == entity_type,
                CatalogTagBinding.entity_id == entity_id,
            )
            .order_by(CatalogTag.name, CatalogTag.id)
        )
    )


def validate_names(db, entity_type, values, entity_id=""):
    clean = normalized_names(values)
    retained = {t.id for t in existing_tags(db, entity_type, entity_id)} if entity_id else set()
    for key in clean:
        tag = find_tag(db, entity_type, key)
        if tag and tag.status != "ACTIVE" and tag.id not in retained:
            raise DomainError("TAG_DISABLED", f"标签「{tag.name}」已停用，不能新增关联", 422)
    return clean


def ensure_tag(
    db, entity_type, display, key, source="INTERNAL", operator_id="legacy", submission_id=None
):
    tag = find_tag(db, entity_type, key)
    if tag:
        return tag
    # A uniqueness constraint arbitrates simultaneous submissions in one scope.
    try:
        with db.begin_nested():
            tag = CatalogTag(
                entity_type=entity_type,
                name=display,
                normalized_name=key,
                source=source,
                operator_id=operator_id,
                submission_id=submission_id,
            )
            db.add(tag)
            db.flush()
    except IntegrityError:
        tag = find_tag(db, entity_type, key)
        if tag is None:
            raise
    return tag


def bind_tags(db, kind, entity_id, values, actor_id, source="INTERNAL", submission_id=None):
    entity_type = TAG_TYPES.get(kind)
    if not entity_type:
        return values
    clean = validate_names(db, entity_type, values, entity_id)
    retained = {t.id for t in existing_tags(db, entity_type, entity_id)}
    tags = [
        ensure_tag(db, entity_type, display, key, source, actor_id, submission_id)
        for key, display in clean.items()
    ]
    if any(t.status != "ACTIVE" and t.id not in retained for t in tags):
        raise DomainError("TAG_DISABLED", "标签已停用，请重新选择", 409)
    wanted = {t.id for t in tags}
    db.execute(
        delete(CatalogTagBinding).where(
            CatalogTagBinding.entity_type == entity_type,
            CatalogTagBinding.entity_id == entity_id,
            CatalogTagBinding.tag_id.not_in(wanted),
        )
    )
    for tag in tags:
        if tag.id not in retained:
            db.add(CatalogTagBinding(entity_type=entity_type, entity_id=entity_id, tag_id=tag.id))
    db.flush()
    return [t.name for t in tags]


def tag_payload(tag):
    return {
        "id": tag.id,
        "name": tag.name,
        "entity_type": tag.entity_type,
        "status": tag.status,
        "source": tag.source,
    }


def entity_tags(db, kind, entity_id):
    tags = existing_tags(db, TAG_TYPES[kind], entity_id)
    return {
        "tags": [t.name for t in tags],
        "tag_ids": [t.id for t in tags],
        "tag_details": [tag_payload(t) for t in tags],
    }
