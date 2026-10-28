"""Missing public catalog submissions. Drafts never bypass the catalog review workflow."""

from pydantic import ValidationError

from app.common.response import DomainError
from app.modules.admin import catalog_service as catalog
from app.modules.admin.console_schemas import EntityDraft
from app.modules.feedback import fields

KINDS = {
    "groups": "组合",
    "idols": "艺人",
    "albums": "专辑",
    "versions": "专辑版本",
    "events": "活动",
    "others": "其他来源",
}


def schema(kind):
    if kind not in KINDS:
        raise DomainError("INVALID_OBJECT", "请选择组合、艺人、专辑、专辑版本、活动或其他来源", 422)
    definitions = list(fields.FIELDS[kind])
    if kind in {"groups", "idols"}:
        definitions += [
            ("aliases", "别名", "list"),
            ("region", "地区", "text"),
            ("cover_image", "背景图片", "image"),
            ("fandom_name", "粉丝名称", "text"),
            ("official_website", "官方网站", "url"),
            ("business_status", "活动状态", "text"),
        ]
        if kind == "idols":
            definitions += [
                ("gender", "性别", "text"),
                ("group_id", "所属组合", "reference", "groups"),
            ]
    elif kind == "versions":
        definitions.insert(0, ("album_id", "所属专辑", "reference", "albums"))
    elif kind == "events":
        definitions += [("end_date", "结束日期", "date"), ("type", "活动类型", "text")]
    elif kind == "others":
        definitions += [("original_name", "原文名称", "text")]
    if kind != "versions":
        definitions += [("tags", "标签", "list")]
    result = []
    for key, label, editor, *reference in definitions:
        limit = 120 if key == "name" else 2000 if key == "description" else 180
        model_field = EntityDraft.model_fields.get(key)
        if model_field and editor not in {"list", "multi_reference", "image"}:
            limit = min(
                [
                    limit,
                    *[
                        constraint.max_length
                        for constraint in model_field.metadata
                        if getattr(constraint, "max_length", None) is not None
                    ],
                ]
            )
        item = {
            "key": key,
            "label": label,
            "type": editor,
            "required": key == "name" or kind == "versions" and key == "album_id",
            "max_length": limit,
        }
        if reference:
            item["reference"] = reference[0]
            item["reference_type"] = reference[0]
        result.append(item)
    return {"entity_type": kind, "label": KINDS[kind], "fields": result}


def validate(db, kind, values, *, user=None, allowed_images=None):
    definitions = {f["key"]: f for f in schema(kind)["fields"]}
    if set(values) - definitions.keys():
        raise DomainError("INVALID_FIELD", "包含不支持的字段，请重新打开表单", 422)
    output, images = {}, {}
    for key, value in values.items():
        definition = definitions[key]
        if definition["type"] == "image" and value is not None and not isinstance(value, str):
            raise DomainError("INVALID_IMAGE", "图片字段须为本次账号上传的图片编号", 422)
        if value in (None, "", []):
            continue
        if definition["type"] == "image":
            if user is not None:
                from app.modules.feedback.service import image_for

                asset = image_for(db, user, value)
                output[key] = asset.image_url
                images[key] = {"id": asset.id, "image_url": asset.image_url}
            elif value not in (allowed_images or set()):
                raise DomainError(
                    "INVALID_IMAGE", "只能采用本次提交的图片；如需更换，请在正式图鉴编辑器处理", 422
                )
            else:
                output[key] = value
        else:
            fields.validate_value(db, definition, value)
            if definition["type"] in {"date", "url"}:
                from app.modules.catalog.profiles import validate_field

                validate_field(db, kind, "", definition, value)
            output[key] = (
                [{"type": v["type"], "id": v["id"]} for v in value]
                if definition["type"] == "multi_reference"
                else value.strip()
                if isinstance(value, str)
                else value
            )
    for key, definition in definitions.items():
        if definition["required"] and not output.get(key):
            raise DomainError("FIELD_REQUIRED", f"请填写{definition['label']}", 422)
    start = output.get("start_date") or (output.get("release_date") if kind == "events" else "")
    if start and output.get("end_date") and output["end_date"] < start:
        raise DomainError("INVALID_DATE_RANGE", "结束日期不能早于开始日期", 422)
    return output, images


def submission(db, user, body):
    if body.entity_id or set(body.missing) - {"scan_session_id", "detected_card_id"}:
        raise DomainError("INVALID_SUBMISSION", "缺失内容不能指定已存在对象或无关字段", 422)
    scan = None
    if body.missing:
        from app.models import DetectedCard, ScanSession

        session = db.get(ScanSession, body.missing.get("scan_session_id"))
        detected = db.get(DetectedCard, body.missing.get("detected_card_id"))
        if (
            not session
            or not detected
            or session.user_id != user.id
            or detected.scan_session_id != session.id
        ):
            raise DomainError("SCAN_NOT_FOUND", "扫描记录不存在", 404)
        scan = {
            "scan_session_id": session.id,
            "detected_card_id": detected.id,
            "original_image_url": session.original_image_url,
            "crop_image_url": detected.crop_image_url,
            "crop_region": detected.crop_region,
        }
    if len({f.key for f in body.fields}) != len(body.fields) or any(
        f.mode != "SET" for f in body.fields
    ):
        raise DomainError("INVALID_FIELD", "请按字段填写缺失内容，不可重复或清空", 422)
    values, images = validate(
        db, body.entity_type, {f.key: f.value for f in body.fields}, user=user
    )
    details = [
        {
            **definition,
            "mode": "SET",
            "current": None,
            "suggested": values[definition["key"]],
            "suggested_display": fields.display_value(db, definition, values[definition["key"]]),
            "image_id": images.get(definition["key"], {}).get("id"),
        }
        for definition in schema(body.entity_type)["fields"]
        if definition["key"] in values
    ]
    return {
        "object": {"name": values["name"], "image_url": values.get("image_url")},
        "catalog": values,
        "catalog_images": images,
        "fields": details,
        "catalog_schema": schema(body.entity_type)["fields"],
        "contributor_name": user.display_name,
        **({"scan": scan} if scan else {}),
    }


def save_draft(db, row, actor, changes):
    # Keep all missing-catalog drafts inside the review until publication. In particular,
    # version records inherit their parent visibility and must not be inserted early.
    original = row.data["catalog"]
    values, _ = validate(
        db,
        row.entity_type,
        {**row.review.get("catalog_draft", original), **changes},
        allowed_images={v["image_url"] for v in row.data.get("catalog_images", {}).values()},
    )
    row.review = {**row.review, "catalog_draft": values}
    return values


def publish(db, row, actor, changes):
    values = save_draft(db, row, actor, changes)
    adopted = [key for key, value in row.data["catalog"].items() if values.get(key) == value]
    if not adopted:
        raise DomainError("NO_FIELDS_ADOPTED", "未采用提交内容，请说明原因并标为未收录", 422)
    from app.modules.feedback.service import check_images_accessible

    check_images_accessible(
        {
            k: image
            for k, image in row.data.get("catalog_images", {}).items()
            if values.get(k) == image["image_url"]
        }
    )
    if row.entity_type == "versions":
        from app.modules.admin.album_versions import sync_after_record, validate_record_name
        from app.modules.admin.catalog_extensions import CatalogRecord, RecordDraft, validate_record

        fields.target(db, "albums", values["album_id"])
        data = {k: v for k, v in values.items() if k != "album_id"}
        body = RecordDraft(entity_type="albums", entity_id=values["album_id"], data=data)
        validate_record(db, "versions", body)
        validate_record_name(db, body)
        entity = CatalogRecord(
            kind="versions",
            entity_type="albums",
            entity_id=body.entity_id,
            data={**body.data, "submission_id": row.id},
        )
        db.add(entity)
        db.flush()
        row.entity_id = entity.id
        sync_after_record(db, body.entity_id)
        catalog.audit(
            db,
            actor,
            "catalog.versions.save",
            "versions",
            entity.id,
            None,
            catalog.row_data(entity),
        )
    else:
        try:
            body = EntityDraft.model_validate(values)
        except ValidationError as exc:
            raise DomainError("INVALID_FIELDS", "请核对字段长度和格式", 422) from exc
        result = catalog.save_entity(
            db, actor, row.entity_type, body, tag_source="USER_SUBMITTED", submission_id=row.id
        )
        row.entity_id = result["id"]
        catalog.transition_entity(db, actor, row.entity_type, row.entity_id, "submit")
        catalog.transition_entity(db, actor, row.entity_type, row.entity_id, "publish")
    row.review = {**row.review, "adopted_fields": adopted}
    row.result = "INCLUDED"
