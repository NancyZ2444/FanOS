"""Validate user suggestions without creating any formal catalog or tag rows."""

from datetime import date

from pydantic import ValidationError
from sqlalchemy import select

from app.common.response import DomainError
from app.models import Card, Group, GroupMembership, Idol

from .tags import TAG_TYPES, find_tag, validate_names

OTHER_FIELDS = {"name", "original_name", "start_date", "end_date", "description", "tags"}


def validate_other_fields(values):
    for field in ("start_date", "end_date"):
        if values.get(field):
            try:
                date.fromisoformat(values[field])
            except (ValueError, TypeError) as exc:
                raise DomainError("INVALID_DATE", "起止日期请使用 YYYY-MM-DD", 422) from exc
    if (
        values.get("start_date")
        and values.get("end_date")
        and values["end_date"] < values["start_date"]
    ):
        raise DomainError("INVALID_DATE", "结束日期不能早于开始日期", 422)


def normalize_suggestion(db, kind, entity_id, suggested):
    from app.modules.admin.catalog_service import MODELS, SOURCE_KINDS, meta_for
    from app.modules.admin.console_schemas import CardDraft, EntityDraft

    values = dict(suggested)
    # Old mobile feedback stored scan context amongst business fields. Keep it
    # with the review, but never apply it as a catalog field.
    context_fields = {
        "missing_kind",
        "notes",
        "source",
        "scan_session_id",
        "detected_card_id",
        "crop_region",
        "crop_image_url",
        "ai_candidates",
        "missing_references",
    }
    context = {key: values.pop(key) for key in list(values) if key in context_fields}
    if context.get("notes") and kind != "cards":
        values.setdefault("description", context["notes"])
    if context.get("missing_kind") == "ALBUM_VERSION":
        if not entity_id:
            raise DomainError("INVALID_SUGGESTION", "新增专辑版本需要选择已有专辑", 422)
        name = values.pop("name", "").strip()
        if not name:
            raise DomainError("INVALID_SUGGESTION", "请填写版本名称", 422)
        values.pop("album_id", None)
        values["versions"] = [name]
        context["append_versions"] = True
    allowed = (
        OTHER_FIELDS
        if kind == "others"
        else set(CardDraft.model_fields if kind == "cards" else EntityDraft.model_fields)
    )
    # Status, operator, copyright approval and arbitrary system fields are not user inputs.
    forbidden = {
        "expected_updated_at",
        "company_ids",
        "company_effective_date",
        "front_source",
        "back_source",
        "source_info",
    }
    if set(values) - (allowed - forbidden):
        raise DomainError("INVALID_SUGGESTION", "存在不支持的补充字段，请刷新后重试", 422)
    # Validate only supplied fields against the admin field types/lengths; do not
    # fill missing fields in a partial correction with draft defaults.
    try:
        schema = CardDraft if kind == "cards" else EntityDraft
        typed = schema.model_validate({"name": "Pending correction", **values}).model_dump()
        values = {key: typed[key] for key in values}
    except ValidationError as exc:
        raise DomainError(
            "INVALID_SUGGESTION", "补充字段格式不正确，请检查名称、标签或关联信息", 422
        ) from exc
    missing = context.get("missing_references", {})
    if (
        not isinstance(missing, dict)
        or set(missing) - {"group_name", "idol_name", "source_name"}
        or any(not isinstance(v, str) or len(v) > 180 for v in missing.values())
    ):
        raise DomainError("INVALID_SUGGESTION", "缺失资料名称格式不正确", 422)
    if kind == "others":
        validate_other_fields(values)
    for key, value in values.items():
        if isinstance(value, str) and len(value) > (2000 if key == "description" else 500):
            raise DomainError("INVALID_SUGGESTION", "补充内容超过字段长度限制", 422)
    for field, model in [("group_id", Group), ("idol_id", Idol)]:
        item_id = values.get(field)
        if item_id:
            meta = meta_for(db, "groups" if model is Group else "idols", item_id)
            if not db.get(model, item_id) or (meta and meta.status != "PUBLISHED"):
                raise DomainError("INVALID_REFERENCE", "请选择已发布的组合或艺人", 422)
    for artist in values.get("artists", []):
        model = {"groups": Group, "idols": Idol}.get(artist.get("type"))
        if not model or not db.get(model, artist.get("id", "")):
            raise DomainError("INVALID_REFERENCE", "请选择已有组合或艺人", 422)
        meta = meta_for(db, artist["type"], artist["id"])
        if meta and meta.status != "PUBLISHED":
            raise DomainError("INVALID_REFERENCE", "请选择已发布的组合或艺人", 422)
    if values.get("group_id") and values.get("idol_id"):
        if not db.scalar(
            select(GroupMembership.id).where(
                GroupMembership.group_id == values["group_id"],
                GroupMembership.idol_id == values["idol_id"],
            )
        ):
            raise DomainError("INVALID_REFERENCE", "所选艺人没有该组合的历史归属", 422)
    if kind == "cards" and values.get("source_entity_id"):
        source_kind = SOURCE_KINDS.get(values.get("source_entity_type"))
        if not source_kind:
            raise DomainError("INVALID_REFERENCE", "来源类型须为 Album、Event 或 Other", 422)
        source = db.get(MODELS[source_kind], values["source_entity_id"])
        meta = meta_for(db, source_kind, values["source_entity_id"])
        if not source or not source.is_published or (meta and meta.status != "PUBLISHED"):
            raise DomainError("INVALID_REFERENCE", "请选择已发布的来源", 422)
    if kind == "cards" and values.get("source_entity_type") not in {
        None,
        "ALBUM",
        "EVENT",
        "OTHER",
    }:
        raise DomainError("INVALID_REFERENCE", "来源类型须为 Album、Event 或 Other", 422)
    if kind in TAG_TYPES and "tags" in values:
        clean = validate_names(db, TAG_TYPES[kind], values["tags"], entity_id)
        values["tags"] = [
            (tag.name if (tag := find_tag(db, TAG_TYPES[kind], key)) else name)
            for key, name in clean.items()
        ]
    if entity_id:
        target = db.get(Card if kind == "cards" else MODELS[kind], entity_id)
        meta = meta_for(db, kind, entity_id)
        if (
            not target
            or (kind == "cards" and target.status != "PUBLISHED")
            or (meta and meta.status != "PUBLISHED")
        ):
            raise DomainError("INVALID_REFERENCE", "请选择已发布的图鉴记录", 422)
    elif not values.get("name" if kind != "cards" else "title"):
        raise DomainError("INVALID_SUGGESTION", "请填写名称", 422)
    return values, context
