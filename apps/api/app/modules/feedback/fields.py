"""Explicit public field allowlists; never serialize arbitrary admin metadata."""

import hashlib
import json
from datetime import date

from sqlalchemy import select

from app.common.response import DomainError
from app.models import Card
from app.modules.admin import catalog_service as catalog
from app.modules.admin.catalog_extensions import CatalogRecord

# key, label, editor, optional reference type / enum options.
BASE = [("name", "名称", "text"), ("image_url", "图片", "image"), ("description", "介绍", "text")]
ACTORS = [("artists", "组合/艺人", "multi_reference", "actors")]
FIELDS = {
    "groups": BASE
    + [
        ("name_translated", "中文名称", "text"),
        ("name_ko", "韩文名称", "text"),
        ("name_en", "英文名称", "text"),
        ("release_date", "出道日期", "date"),
    ],
    "idols": BASE
    + [
        ("name_translated", "中文名称", "text"),
        ("name_ko", "韩文名称", "text"),
        ("name_en", "英文名称", "text"),
        ("real_name", "本名", "text"),
        ("release_date", "出生日期", "date"),
    ],
    "albums": BASE
    + ACTORS
    + [
        ("release_date", "发行日期", "date"),
        ("type", "发行类型", "text"),
        ("versions", "发行版本", "list"),
    ],
    "events": BASE
    + ACTORS
    + [
        ("release_date", "开始日期", "date"),
        ("is_online", "线上活动", "boolean"),
        ("city", "城市", "text"),
        ("platform", "平台", "text"),
        ("venue", "场馆", "text"),
    ],
    "others": BASE
    + ACTORS
    + [("start_date", "开始日期", "date"), ("end_date", "结束日期", "date")],
    "cards": [
        ("idol_id", "所属艺人", "reference", "idols"),
        ("group_id", "所属组合", "reference", "groups"),
        ("source_entity_id", "来源", "reference", "sources"),
        ("entity_version_id", "版本", "reference", "versions"),
        ("image_url", "正面图片", "image"),
        ("back_image_url", "背面图片", "image"),
        ("card_type", "小卡类型", "text"),
        ("release_date", "发行日期", "date"),
        ("region", "地区", "text"),
    ],
    "versions": [
        ("name", "版本名称", "text"),
        ("image_url", "版本图片", "image"),
        ("description", "介绍", "text"),
    ],
    "companies": BASE,
}


def digest(value):
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True, default=str).encode()
    ).hexdigest()


def target(db, kind, item_id, published=True):
    if kind not in FIELDS:
        raise DomainError("INVALID_OBJECT", "不支持的反馈对象", 422)
    if kind in {"versions", "companies"}:
        row = db.get(CatalogRecord, item_id)
        if not row or row.kind != kind:
            raise DomainError("OBJECT_UNAVAILABLE", "图鉴内容不存在", 404)
        raw = {
            **row.data,
            "id": row.id,
            "status": row.status,
            "updated_at": row.updated_at.isoformat(),
        }
        if kind == "versions" and row.status not in {"ARCHIVED", "OFFLINE"}:
            target(db, row.entity_type, row.entity_id)
            raw["status"] = "PUBLISHED"  # Versions inherit their published source's visibility.
        if kind == "companies" and row.status not in {"ARCHIVED", "OFFLINE"}:
            # Company records have no publish workflow. Expose only companies already
            # attached to a publicly visible group or idol, not unused admin drafts.
            relations = db.scalars(
                select(CatalogRecord).where(
                    CatalogRecord.kind == "company_relations", CatalogRecord.status != "ARCHIVED"
                )
            )
            for relation in relations:
                if relation.data.get("company_id") != row.id:
                    continue
                try:
                    target(db, relation.entity_type, relation.entity_id)
                    raw["status"] = "PUBLISHED"
                    break
                except DomainError:
                    continue
    else:
        row = db.get(Card if kind == "cards" else catalog.MODELS[kind], item_id)
        if not row:
            raise DomainError("OBJECT_UNAVAILABLE", "图鉴内容不存在", 404)
        raw = (
            catalog.admin_card(db, row)
            if kind == "cards"
            else catalog.entity_payload(db, kind, row)
        )
        raw["release_date"] = (
            raw.get("release_date")
            or raw.get("debut_date")
            or raw.get("birth_date")
            or raw.get("start_date", "")
        )
        raw["description"] = raw.get("description") or raw.get("bio", "")
    if published and raw.get("status") != "PUBLISHED":
        raise DomainError("OBJECT_UNAVAILABLE", "图鉴内容暂不可用", 404)
    return row, raw


def description(db, kind, item_id):
    row, raw = target(db, kind, item_id)
    fields = []
    visible_names = set()
    if kind in {"groups", "idols"}:
        seen_names = set()
        for key in ("name_translated", "name", "name_ko", "name_en", "real_name"):
            value = (raw.get(key) or "").strip()
            if value and value not in seen_names and len(visible_names) < 2:
                visible_names.add(key)
                seen_names.add(value)
    for entry in FIELDS[kind]:
        key, label, editor = entry[:3]
        if (
            kind in {"groups", "idols"}
            and key in {"name_translated", "name", "name_ko", "name_en", "real_name"}
            and key not in visible_names
        ):
            continue
        if kind == "events" and (
            (key in {"city", "venue"} and raw.get("is_online"))
            or (key == "platform" and not raw.get("is_online"))
        ):
            continue
        field = {"key": key, "label": label, "type": editor, "current": raw.get(key)}
        if len(entry) > 3:
            field["options" if editor == "enum" else "reference_type"] = entry[3]
            if editor != "enum":
                field["reference"] = entry[3]
        # Transport IDs remain stable for validation; never render them as names.
        field["current_display"] = display_value(db, field, field["current"])
        if kind == "cards" and key == "entity_version_id":
            field["current_display"] = field["current_display"] or raw.get("version", "")
            field["parent_id"] = raw.get("source_entity_id")
        fields.append(field)
    if kind == "cards":
        from app.common.serializers import card_payload

        public = card_payload(db, row)
        name = (
            " · ".join(str(public[k]) for k in ("source", "version", "card_type") if public.get(k))
            or "小卡"
        )
    else:
        name = raw.get("name_translated") or raw.get("name") or "图鉴对象"
    return {
        "entity_type": kind,
        "entity_id": item_id,
        "name": name,
        "image_url": raw.get("image_url"),
        "fields": fields,
        "version": digest(raw),
    }


def display_value(db, field, value):
    if value is None or value == "" or value == []:
        return ""
    editor = field["type"]
    if editor == "multi_reference":
        return " · ".join(reference_name(db, v.get("type"), v.get("id")) for v in value)
    if editor == "reference":
        kind = field["reference_type"]
        kinds = ["albums", "events", "others"] if kind == "sources" else [kind]
        return next((name for k in kinds if (name := reference_name(db, k, value))), "")
    if editor == "boolean":
        return "是" if value else "否"
    if editor == "list":
        return " · ".join(str(v) for v in value)
    return str(value)


def reference_name(db, kind, item_id):
    try:
        _, raw = target(db, kind, item_id, published=False)
        return raw.get("name_translated") or raw.get("name") or ""
    except (DomainError, KeyError):
        return ""


def search_objects(db, kind, q="", limit=50, parent_id=None):
    kinds = (
        ["groups", "idols"]
        if kind == "actors"
        else ["albums", "events", "others"]
        if kind == "sources"
        else [kind]
    )
    result = []
    for k in kinds:
        if k not in FIELDS:
            raise DomainError("INVALID_OBJECT", "不支持的对象类型", 422)
        if k in {"versions", "companies"}:
            ids = db.scalars(
                select(CatalogRecord.id).where(
                    CatalogRecord.kind == k, CatalogRecord.status.not_in(["ARCHIVED", "OFFLINE"])
                )
            ).all()
        else:
            model = Card if k == "cards" else catalog.MODELS[k]
            ids = db.scalars(select(model.id)).all()
        for item_id in ids:
            if (
                k == "versions"
                and parent_id
                and db.get(CatalogRecord, item_id).entity_id != parent_id
            ):
                continue
            try:
                obj = description(db, k, item_id)
            except DomainError:
                continue
            if not q or q.casefold() in obj["name"].casefold():
                result.append(
                    {
                        "id": obj["entity_id"],
                        **{
                            key: obj[key]
                            for key in ("entity_type", "entity_id", "name", "image_url")
                        },
                    }
                )
            if len(result) >= limit:
                return result
    return result


def validate_value(db, field, value):
    kind = field["type"]
    if kind == "boolean":
        if not isinstance(value, bool):
            raise DomainError("INVALID_VALUE", "请选择是或否", 422)
    elif kind == "list":
        if (
            not isinstance(value, list)
            or len(value) > 30
            or any(not isinstance(v, str) or not v.strip() or len(v) > 120 for v in value)
        ):
            raise DomainError("INVALID_VALUE", "列表最多30项，每项1–120字", 422)
    elif kind == "multi_reference":
        if not isinstance(value, list) or not value or len(value) > 20:
            raise DomainError("INVALID_VALUE", "请选择1–20个组合/艺人", 422)
        for v in value:
            if not isinstance(v, dict) or v.get("type") not in {"groups", "idols"}:
                raise DomainError("INVALID_VALUE", "归属对象无效", 422)
            target(db, v["type"], v.get("id"))
    else:
        if not isinstance(value, str) or not value.strip() or len(value) > 2000:
            raise DomainError("INVALID_VALUE", "请填写建议值（最多2000字）", 422)
        if kind == "date":
            try:
                date.fromisoformat(value)
            except ValueError as e:
                raise DomainError("INVALID_VALUE", "日期格式为YYYY-MM-DD", 422) from e
        if kind == "enum" and value not in field["options"]:
            raise DomainError("INVALID_VALUE", "选项无效", 422)
        if kind == "reference":
            types = {"sources": ["albums", "events", "others"]}.get(
                field["reference_type"], [field["reference_type"]]
            )
            for k in types:
                try:
                    target(db, k, value)
                    break
                except DomainError:
                    continue
            else:
                raise DomainError("INVALID_VALUE", "关联对象不可用", 422)
