from contextlib import contextmanager
from datetime import UTC, datetime
from io import BytesIO

from PIL import Image, ImageOps
from sqlalchemy import select, update

from app.admin_models import CardImageVersion
from app.common.response import DomainError
from app.common.serializers import card_payload
from app.future_models import NotificationInboxItem
from app.integrations.storage import get_storage
from app.models import Card, DetectedCard, ScanCandidate, ScanSession, User
from app.modules.admin import catalog_service as catalog
from app.modules.admin.console_schemas import CardDraft, EntityDraft
from app.modules.feedback.fields import description, digest, display_value, target, validate_value
from app.modules.feedback.models import CardContribution, Feedback, FeedbackImage, FeedbackNotice


def now():
    return datetime.now(UTC).isoformat()


def image_for(db, user, image_id):
    asset = db.get(FeedbackImage, image_id) if image_id else None
    if not asset or asset.user_id != user.id:
        raise DomainError("INVALID_IMAGE", "请选择本次账号上传的图片", 422)
    return asset


def save_image(db, user, content, crop=None):
    if len(content) > 10 * 1024 * 1024:
        raise DomainError("IMAGE_TOO_LARGE", "图片不能超过10MB", 422)
    try:
        with Image.open(BytesIO(content)) as original:
            if (
                original.format not in {"JPEG", "PNG", "WEBP"}
                or original.width * original.height > 24_000_000
            ):
                raise ValueError()
            image = ImageOps.exif_transpose(original).convert("RGB")
            if crop:
                x, y, w, h = crop
                if not (
                    0 <= x < 1
                    and 0 <= y < 1
                    and w > 0
                    and h > 0
                    and x + w <= 1.001
                    and y + h <= 1.001
                ):
                    raise ValueError()
                image = image.crop(
                    (
                        int(x * image.width),
                        int(y * image.height),
                        int((x + w) * image.width),
                        int((y + h) * image.height),
                    )
                )
            image.thumbnail((2000, 2800))
            output = BytesIO()
            image.save(output, format="JPEG", quality=90)
    except (ValueError, OSError, Image.DecompressionBombError) as e:
        raise DomainError("INVALID_IMAGE", "请选择有效JPG、PNG或WebP，最多2400万像素", 422) from e
    asset = FeedbackImage(
        user_id=user.id,
        image_url=get_storage().save_bytes(output.getvalue(), "feedback.jpg", "feedback"),
    )
    db.add(asset)
    db.flush()
    return asset


def lock_user(db, user):
    # Serializes idempotency checks in SQLite and PostgreSQL, without touching profile data.
    db.execute(update(User).where(User.id == user.id).values(updated_at=User.updated_at))


def submit(db, user, body):
    lock_user(db, user)
    existing = db.scalar(
        select(Feedback).where(
            Feedback.user_id == user.id, Feedback.request_key == body.request_key
        )
    )
    signature = digest(body.model_dump())
    if existing:
        if existing.data.get("request_hash") != signature:
            raise DomainError("IDEMPOTENCY_CONFLICT", "同一请求编号不能提交不同内容", 409)
        return existing
    evidence = [{"id": i, "image_url": image_for(db, user, i).image_url} for i in body.evidence_ids]
    content = {
        "request_hash": signature,
        "notes": body.notes,
        "evidence": evidence,
        "links": body.links,
    }
    if body.kind == "CORRECTION":
        obj = description(db, body.entity_type, body.entity_id)
        if body.object_version != obj["version"]:
            raise DomainError("OBJECT_CHANGED", "资料已更新，请刷新字段后重新核对", 409)
        by_key = {f["key"]: f for f in obj["fields"]}
        if not body.fields or len({f.key for f in body.fields}) != len(body.fields):
            raise DomainError("FIELDS_REQUIRED", "请选择至少一个不重复的问题字段", 422)
        details = []
        for change in body.fields:
            field = by_key.get(change.key)
            if not field:
                raise DomainError("INVALID_FIELD", "该字段不能反馈", 422)
            if change.mode == "UNKNOWN" and not (change.reason.strip() or body.notes.strip()):
                raise DomainError("REASON_REQUIRED", "未知正确值时须说明问题", 422)
            proposed = change.value
            image_id = None
            if change.mode == "SET":
                if field["type"] == "image":
                    asset = image_for(db, user, proposed)
                    proposed = asset.image_url
                    image_id = asset.id
                else:
                    validate_value(db, field, proposed)
                if proposed == field["current"]:
                    raise DomainError("UNCHANGED_VALUE", "建议值与当前值相同，请调整", 422)
            if (
                change.mode == "CLEAR"
                and field["current"] in (None, "", [])
                and not field.get("current_display")
            ):
                raise DomainError("UNCHANGED_VALUE", "当前字段已为空", 422)
            details.append(
                {
                    **field,
                    "mode": change.mode,
                    "suggested": proposed if change.mode == "SET" else None,
                    "suggested_display": display_value(db, field, proposed)
                    if change.mode == "SET"
                    else "",
                    "reason": change.reason,
                    "image_id": image_id,
                }
            )
        content.update(object=obj, fields=details)
    else:
        values = dict(body.missing)
        session = db.get(ScanSession, values.get("scan_session_id"))
        detected = db.get(DetectedCard, values.get("detected_card_id"))
        if (
            not session
            or not detected
            or session.user_id != user.id
            or detected.scan_session_id != session.id
        ):
            raise DomainError("SCAN_NOT_FOUND", "扫描记录不存在", 404)
        from app.modules.scan.router import _validate_feedback_actors, _validate_source_reference

        if (
            not values.get("group_id")
            or not values.get("is_group_pc")
            and not values.get("idol_id")
        ):
            raise DomainError("ACTOR_REQUIRED", "请选择组合及艺人，团体小卡可免选艺人", 422)
        _validate_feedback_actors(db, values["group_id"], values.get("idol_id"))
        source_type = values.get("source_entity_type")
        if source_type not in {"ALBUM", "EVENT", "OTHER"}:
            raise DomainError("SOURCE_REQUIRED", "请选择专辑、活动或其他来源", 422)
        if values.get("source_entity_id"):
            resolved = _validate_source_reference(
                db,
                {
                    **values,
                    "source_mode": "KNOWN",
                    "source": {"ALBUM": "专辑", "EVENT": "活动", "OTHER": "其他"}[source_type],
                },
            )
            values.update(resolved)
        elif not str(values.get("missing_source_name", "")).strip():
            raise DomainError("SOURCE_REQUIRED", "请选择来源或填写缺失来源名称", 422)
        if values.get("front_image_id"):
            front = image_for(db, user, values["front_image_id"])
        else:
            front = FeedbackImage(user_id=user.id, image_url=detected.crop_image_url)
            db.add(front)
            db.flush()
        back = image_for(db, user, values["back_image_id"]) if values.get("back_image_id") else None
        if values.get("is_double_sided") and not back:
            raise DomainError("BACK_REQUIRED", "双面小卡必须上传背面图片", 422)
        if not front.image_url:
            raise DomainError("FRONT_REQUIRED", "请上传正面图片", 422)
        allowed = {
            "group_id",
            "idol_id",
            "is_group_pc",
            "is_double_sided",
            "source_entity_type",
            "source_entity_id",
            "source_version_id",
            "source_version_name",
            "source_name",
            "missing_source_name",
            "title",
            "version",
            "card_type",
        }
        values = {k: v for k, v in values.items() if k in allowed}
        if values.get("is_group_pc"):
            values["idol_id"] = None
        content.update(
            missing=values,
            front={"id": front.id, "image_url": front.image_url},
            back={"id": back.id, "image_url": back.image_url} if back else None,
            scan={
                "scan_session_id": session.id,
                "detected_card_id": detected.id,
                "original_image_url": session.original_image_url,
                "crop_image_url": detected.crop_image_url,
                "crop_region": detected.crop_region,
                "candidates": [
                    {"card_id": c.card_id, "similarity": c.similarity}
                    for c in db.scalars(
                        select(ScanCandidate).where(ScanCandidate.detected_card_id == detected.id)
                    )
                ],
            },
        )
    row = Feedback(
        user_id=user.id,
        request_key=body.request_key,
        kind=body.kind,
        entity_type=body.entity_type if body.kind == "CORRECTION" else "cards",
        entity_id=body.entity_id if body.kind == "CORRECTION" else "",
        data=content,
        history=[{"at": now(), "status": "PENDING", "result": "PENDING", "note": "已收到反馈"}],
    )
    db.add(row)
    db.flush()
    return row


def label(row):
    if row.result == "INCLUDED":
        return "已收录"
    if row.result == "NOT_INCLUDED":
        return "未收录" if row.kind == "MISSING_CARD" else "已处理"
    return {"PENDING": "待处理", "PROCESSING": "处理中", "PROCESSED": "已处理"}[row.status]


def payload(db, row, admin=False):
    obj = row.data.get("object", {})
    available = False
    if row.entity_id:
        try:
            target(db, row.entity_type, row.entity_id)
            available = True
        except DomainError:
            pass
    decisions = row.review.get("decisions", [])
    result = {
        "id": row.id,
        "kind": row.kind,
        "entity_type": row.entity_type,
        "entity_id": row.entity_id,
        "status": row.status,
        "result": row.result,
        "status_label": label(row),
        "revision": row.revision,
        "name": obj.get("name") or row.data.get("missing", {}).get("title") or "小卡缺失反馈",
        "image_url": obj.get("image_url") or row.data.get("front", {}).get("image_url"),
        "created_at": row.created_at.isoformat(),
        "updated_at": row.updated_at.isoformat(),
        "public_note": row.public_note,
        "history": row.history,
        "target_available": available,
        "submission": {k: v for k, v in row.data.items() if k != "request_hash"},
        "decisions": decisions,
    }
    if admin:
        user = db.get(User, row.user_id)
        result.update(
            user={"id": row.user_id, "name": user.display_name if user else "已注销用户"},
            internal_note=row.internal_note,
            handler_id=row.handler_id,
            review=row.review,
        )
        if row.entity_id:
            try:
                _, raw = target(db, row.entity_type, row.entity_id, False)
                result["latest"] = (
                    description(db, row.entity_type, row.entity_id)
                    if raw["status"] == "PUBLISHED"
                    else {"version": digest(raw), "fields": []}
                )
                result["draft"] = raw if row.kind == "MISSING_CARD" else None
            except DomainError:
                result["latest"] = None
    return result


def event(db, row, note):
    row.revision += 1
    row.history = [
        *row.history,
        {"at": now(), "status": row.status, "result": row.result, "note": note},
    ]
    if row.status == "PROCESSED":
        notice_id = f"{row.id}:{row.revision}"
        db.add(
            FeedbackNotice(
                id=notice_id,
                user_id=row.user_id,
                data={
                    "feedback_id": row.id,
                    "title": f"反馈{label(row)}",
                    "body": note[:500],
                    "status": row.status,
                    "result": row.result,
                },
            )
        )


def deliver_notices(db, user_id=None):
    query = select(FeedbackNotice).where(FeedbackNotice.delivered.is_(False))
    if user_id:
        query = query.where(FeedbackNotice.user_id == user_id)
    ids = list(db.scalars(query.limit(100)))
    for notice in ids:
        notice_id = notice.id
        try:
            # A deterministic inbox ID makes retry and concurrent delivery idempotent.
            if not db.get(NotificationInboxItem, notice_id):
                db.add(
                    NotificationInboxItem(
                        id=notice_id,
                        user_id=notice.user_id,
                        category="CATALOG_FEEDBACK",
                        source_type="feedback",
                        source_id=notice.data["feedback_id"],
                        title=notice.data["title"],
                        body=notice.data["body"],
                        payload={"feedback_id": notice.data["feedback_id"]},
                    )
                )
            notice.delivered = True
            notice.error = ""
            db.commit()
        except Exception as e:
            db.rollback()
            failed = db.get(FeedbackNotice, notice_id)
            failed.error = type(e).__name__
            db.commit()


def image_origins(db, row, card, actor, adopted):
    for side, asset in adopted.items():
        version = db.scalar(
            select(CardImageVersion)
            .where(CardImageVersion.card_id == card.id, CardImageVersion.side == side)
            .order_by(CardImageVersion.version.desc())
        )
        if not version or version.data.get("image_url") != asset["image_url"]:
            continue
        # Original submission identity and actual source never change on promotion.
        provenance = {
            "feedback_id": row.id,
            "user_id": row.user_id,
            "original_image_version_id": asset["id"],
        }
        origins = list(version.data.get("submissions", []))
        if provenance not in origins:
            origins.append(provenance)
        version.data = {
            **version.data,
            "source_type": "USER_SUBMITTED",
            "version_identity": "OFFICIAL_CATALOG",
            "submissions": origins,
            "converted_by": actor.id,
            "converted_at": now(),
        }
        if not db.scalar(
            select(CardContribution.id).where(
                CardContribution.feedback_id == row.id,
                CardContribution.image_version_id == version.id,
            )
        ):
            db.add(
                CardContribution(
                    card_id=card.id,
                    user_id=row.user_id,
                    feedback_id=row.id,
                    image_version_id=version.id,
                )
            )


def draft_missing(db, row, actor, changes):
    current = {}
    if row.entity_id:
        _, current = target(db, "cards", row.entity_id, False)
    else:
        source = row.data["missing"]
        current = {k: v for k, v in source.items() if k in CardDraft.model_fields}
        current["entity_version_id"] = source.get("source_version_id")
        if str(current.get("entity_version_id", "")).startswith("legacy_version_"):
            # Legacy source arrays have no editable ID until an operator creates the draft.
            from app.models import CatalogAlbum
            from app.modules.admin.album_versions import ensure_versions

            album = db.get(CatalogAlbum, source.get("source_entity_id"))
            if album and source.get("source_version_name"):
                ids, _ = ensure_versions(db, actor, album, [source["source_version_name"]])
                current["entity_version_id"] = ids[0]
                current["version"] = source["source_version_name"]
            else:
                current["entity_version_id"] = None
        for field, key in [("image_url", "front"), ("back_image_url", "back")]:
            current[field] = (row.data.get(key) or {}).get("image_url")
            current["front_source" if key == "front" else "back_source"] = {
                "source_type": "USER_SUBMITTED"
            }
    if current.get("status") == "PUBLISHED":
        raise DomainError("DRAFT_PUBLISHED", "关联草稿已发布，请重新核实该反馈，不能重复创建", 409)
    values = {**current, **changes}
    values["source_entity_id"] = values.get("source_entity_id") or ""
    if str(values.get("entity_version_id", "")).startswith("legacy_version_"):
        values["entity_version_id"] = current.get("entity_version_id")
        values["version"] = current.get("version", "")
    for side in ["front", "back"]:
        field = "image_url" if side == "front" else "back_image_url"
        if row.data.get(side) and values.get(field) == row.data[side]["image_url"]:
            values[f"{side}_source"] = {
                **values.get(f"{side}_source", {}),
                "source_type": "USER_SUBMITTED",
            }
    saved = catalog.save_card(
        db,
        actor,
        CardDraft.model_validate(values),
        row.entity_id or None,
        tag_source="USER_SUBMITTED",
        submission_id=row.id,
    )
    row.entity_id = saved.id
    # Preserve submission identity even before publication.
    for v in db.scalars(select(CardImageVersion).where(CardImageVersion.card_id == saved.id)):
        key = "front" if v.side == "FRONT" else "back"
        asset = row.data.get(key)
        if asset and v.data.get("image_url") == asset["image_url"]:
            v.data = {
                **v.data,
                "version_identity": "USER_SUBMITTED",
                "submissions": [
                    {
                        "feedback_id": row.id,
                        "user_id": row.user_id,
                        "original_image_version_id": asset["id"],
                    }
                ],
            }
    return saved


def check_images_accessible(images):
    for asset in images.values():
        try:
            content = get_storage().read_bytes(asset["image_url"])
            with Image.open(BytesIO(content)) as image:
                image.verify()
        except Exception as e:
            raise DomainError(
                "IMAGE_UNAVAILABLE", "采用的用户图片当前不可访问，请修复后再发布", 422
            ) from e


def publish_correction(db, row, actor, body):
    locked, _ = target(db, row.entity_type, row.entity_id)
    model = type(locked)
    db.execute(update(model).where(model.id == locked.id).values(updated_at=model.updated_at))
    db.refresh(locked)
    obj = description(db, row.entity_type, row.entity_id)
    if body.object_version != obj["version"]:
        raise DomainError("OBJECT_CHANGED", "对象已变化，请重新核对平台最新值后再发布", 409)
    decisions = body.decisions or row.review.get("decisions", [])
    submitted = {f["key"]: f for f in row.data["fields"]}
    if {d["key"] for d in decisions} != set(submitted) or len(decisions) != len(submitted):
        raise DomainError("DECISIONS_REQUIRED", "请处理每一个反馈字段", 422)
    changes = {}
    adopted = {}
    actual = []
    for decision in decisions:
        field = submitted[decision["key"]]
        decision = dict(decision)
        if decision["decision"] == "REJECT":
            if not decision.get("reason", "").strip():
                raise DomainError("REASON_REQUIRED", "未采纳字段必须填写原因", 422)
        elif decision["decision"] in {"ACCEPT", "MODIFY"}:
            value = (
                decision.get("value") if decision["decision"] == "MODIFY" else field["suggested"]
            )
            if field["mode"] == "UNKNOWN" and decision["decision"] == "ACCEPT":
                raise DomainError("VALUE_REQUIRED", "未知正确值须由运营填写采用值", 422)
            if field["mode"] == "CLEAR" and decision["decision"] == "ACCEPT":
                value = (
                    []
                    if field["type"] in {"list", "multi_reference"}
                    else False
                    if field["type"] == "boolean"
                    else None
                    if field["type"] in {"image", "reference"}
                    else ""
                )
            elif field["type"] != "image":
                validate_value(db, field, value)
            elif value != field["suggested"]:
                raise DomainError("IMAGE_REQUIRED", "图片采用需使用该条反馈上传图片", 422)
            decision["value"] = value
            decision["value_display"] = display_value(db, field, value)
            # Historical submissions stay reviewable, but retired system fields
            # cannot be adopted after the public correction contract narrows.
            current_field = next((f for f in obj["fields"] if f["key"] == field["key"]), None)
            if current_field is None:
                raise DomainError("FIELD_RETIRED", "该字段已停止接受纠错，请填写原因并不采纳", 422)
            latest = current_field["current"]
            clearing_legacy_version = (
                field["key"] == "entity_version_id"
                and value is None
                and latest is None
                and bool(current_field.get("current_display"))
            )
            if value == latest and not clearing_legacy_version:
                decision.update(decision="REJECT", reason="平台最新值已修正，本次未重复修改")
                actual.append(decision)
                continue
            changes[field["key"]] = value
            if field["type"] == "image" and value and field.get("image_id"):
                adopted["FRONT" if field["key"] == "image_url" else "BACK"] = {
                    "id": field["image_id"],
                    "image_url": value,
                }
        else:
            raise DomainError("INVALID_DECISION", "审核决定无效", 422)
        actual.append(decision)
    if not changes:
        row.result = "NOT_INCLUDED"
        row.review = {**row.review, "decisions": actual}
        return
    check_images_accessible(adopted)
    old, raw = target(db, row.entity_type, row.entity_id)
    if row.entity_type == "cards":
        if "entity_version_id" in changes and not changes["entity_version_id"]:
            # A cleared relation must not fall back to the legacy free-text version.
            changes["version"] = ""
        if changes.get("source_entity_id"):
            for kind, source_type in [
                ("albums", "ALBUM"),
                ("events", "EVENT"),
                ("others", "OTHER"),
            ]:
                if db.get(catalog.MODELS[kind], changes["source_entity_id"]):
                    changes["source_entity_type"] = source_type
                    break
            if "entity_version_id" not in changes:
                changes.update(entity_version_id=None, version="")
        for side in adopted:
            key = "front_source" if side == "FRONT" else "back_source"
            info = body.sources.get(key, {})
            if info.get("copyright_status") not in {"AUTHORIZED", "OFFICIAL_SOURCE"}:
                raise DomainError("COPYRIGHT_REQUIRED", "请独立确认采用图片的使用状态", 422)
            changes[key] = {**info, "source_type": "USER_SUBMITTED"}
        catalog.transition_card(db, actor, old.id, "offline")
        # Lifecycle transitions change updated_at, so compare the version before transition.
        card = catalog.save_card(
            db,
            actor,
            CardDraft.model_validate({**raw, **changes, "expected_updated_at": None}),
            old.id,
            submission_id=row.id,
        )
        catalog.transition_card(db, actor, old.id, "submit")
        catalog.transition_card(db, actor, old.id, "publish")
        image_origins(db, row, card, actor, adopted)
    elif row.entity_type in {"companies", "versions"}:
        if adopted and body.sources.get("source_info", {}).get("copyright_status") not in {
            "AUTHORIZED",
            "OFFICIAL_SOURCE",
        }:
            raise DomainError("COPYRIGHT_REQUIRED", "请确认图片的使用状态", 422)
        if adopted:
            changes["source_info"] = {
                **body.sources["source_info"],
                "source_type": "USER_SUBMITTED",
            }
        if not (changes.get("name", raw.get("name")) or "").strip():
            raise DomainError("NAME_REQUIRED", "名称不能为空", 422)
        previous_name = old.data.get("name")
        if row.entity_type == "versions" and old.entity_type == "albums":
            from types import SimpleNamespace

            from app.modules.admin.album_versions import sync_after_record, validate_record_name

            record = SimpleNamespace(data={**old.data, **changes}, entity_id=old.entity_id)
            validate_record_name(db, record, old.id)
            old.data = record.data
            sync_after_record(db, old.entity_id, previous_name)
        else:
            old.data = {**old.data, **changes}
    else:
        if adopted and body.sources.get("source_info", {}).get("copyright_status") not in {
            "AUTHORIZED",
            "OFFICIAL_SOURCE",
        }:
            raise DomainError("COPYRIGHT_REQUIRED", "请确认图片的使用状态", 422)
        if adopted:
            changes["source_info"] = {
                **body.sources["source_info"],
                "source_type": "USER_SUBMITTED",
            }
        catalog.transition_entity(db, actor, row.entity_type, old.id, "offline")
        # Read models contain derived company selections, not edit commands.
        editable = {
            k: v for k, v in raw.items() if k not in {"company_ids", "company_effective_date"}
        }
        catalog.save_entity(
            db,
            actor,
            row.entity_type,
            EntityDraft.model_validate({**editable, **changes}),
            old.id,
            submission_id=row.id,
        )
        catalog.transition_entity(db, actor, row.entity_type, old.id, "submit")
        catalog.transition_entity(db, actor, row.entity_type, old.id, "publish")
    row.review = {**row.review, "decisions": actual}
    row.result = "INCLUDED"


def act(db, row, actor, body):
    catalog.permit(
        actor,
        "catalog",
        "publish" if body.action in {"publish", "reject", "match", "already_fixed"} else "edit",
    )
    db.execute(
        update(Feedback)
        .where(Feedback.id == row.id)
        .values(revision=Feedback.revision, updated_at=Feedback.updated_at)
    )
    db.refresh(row)
    action_hashes = dict(row.review.get("action_hashes", {}))
    if body.request_key in row.action_keys:
        if row.review.get("action_hashes", {}).get(body.request_key) != digest(body.model_dump()):
            raise DomainError("IDEMPOTENCY_CONFLICT", "同一操作编号不能用于不同内容", 409)
        return row
    if body.revision != row.revision:
        raise DomainError("FEEDBACK_CHANGED", "反馈已被其他操作更新，请刷新", 409)
    if row.result != "PENDING":
        raise DomainError("FEEDBACK_COMPLETED", "反馈已完成，不可重复处理", 409)
    if (
        body.action in {"reject", "match", "already_fixed", "publish"}
        and not body.public_note.strip()
    ):
        raise DomainError("REASON_REQUIRED", "请填写面向用户的处理说明", 422)
    row.handler_id = actor.id
    row.internal_note = body.internal_note
    if body.action == "start":
        row.status = "PROCESSING"
    elif body.action == "review":
        if row.kind != "CORRECTION":
            raise DomainError("INVALID_ACTION", "缺失收录请保存小卡草稿", 422)
        row.review = {"decisions": body.decisions, "object_version": body.object_version}
        row.status = "PROCESSED"
    elif body.action == "draft":
        if row.kind != "MISSING_CARD":
            raise DomainError("INVALID_ACTION", "纠错不能创建小卡", 422)
        draft_missing(db, row, actor, body.changes)
        row.status = "PROCESSED"
    elif body.action == "reject":
        row.status = "PROCESSED"
        row.result = "NOT_INCLUDED"
    elif body.action in {"match", "already_fixed"}:
        if body.action == "match" and row.kind != "MISSING_CARD":
            raise DomainError("INVALID_ACTION", "纠错不能匹配其他小卡", 422)
        if body.action == "already_fixed" and row.kind != "CORRECTION":
            raise DomainError("INVALID_ACTION", "操作不适用", 422)
        if body.action == "match":
            row.entity_id = body.card_id or ""
        target(db, row.entity_type, row.entity_id)
        row.status = "PROCESSED"
        row.result = "NOT_INCLUDED"
    elif body.action == "publish":
        # Nested transaction ensures even publish validation failures leave no partial edits.
        with db.begin_nested(), feedback_publication(db, row.id):
            if row.kind == "MISSING_CARD":
                card = draft_missing(db, row, actor, body.changes)
                adopted = {
                    side: row.data[key]
                    for side, key in [("FRONT", "front"), ("BACK", "back")]
                    if row.data.get(key)
                    and (
                        card.image_url if side == "FRONT" else card.admin_data.get("back_image_url")
                    )
                    == row.data[key]["image_url"]
                }
                if not adopted:
                    raise DomainError(
                        "NO_IMAGE_ADOPTED",
                        "未采用提交图片不能标记收录，请匹配已有小卡或说明原因",
                        422,
                    )
                check_images_accessible(adopted)
                catalog.transition_card(db, actor, card.id, "submit")
                catalog.transition_card(db, actor, card.id, "publish")
                image_origins(db, row, card, actor, adopted)
                row.result = "INCLUDED"
            else:
                publish_correction(db, row, actor, body)
        row.status = "PROCESSED"
    else:
        raise DomainError("INVALID_ACTION", "不支持的处理操作", 422)
    row.public_note = body.public_note or (
        "正在核实" if body.action == "start" else "审核已处理，待正式发布"
    )
    row.action_keys = [*row.action_keys, body.request_key]
    row.review = {
        **row.review,
        "action_hashes": {**action_hashes, body.request_key: digest(body.model_dump())},
    }
    event(db, row, row.public_note)
    catalog.audit(
        db,
        actor,
        "feedback." + body.action,
        "feedback",
        row.id,
        None,
        {"revision": row.revision, "status": row.status, "result": row.result},
    )
    db.flush()
    return row


@contextmanager
def feedback_publication(db, feedback_id):
    previous = db.info.get("active_feedback_publication")
    db.info["active_feedback_publication"] = feedback_id
    try:
        yield
    finally:
        db.info["active_feedback_publication"] = previous


def catalog_card_published(db, card, actor):
    """Also reconcile linked feedback when an operator publishes in the full editor."""
    rows = db.scalars(
        select(Feedback).where(
            Feedback.kind == "MISSING_CARD",
            Feedback.entity_id == card.id,
            Feedback.result == "PENDING",
        )
    ).all()
    for row in rows:
        if row.id == db.info.get("active_feedback_publication"):
            continue
        adopted = {
            side: row.data[key]
            for side, key in [("FRONT", "front"), ("BACK", "back")]
            if row.data.get(key)
            and (card.image_url if side == "FRONT" else card.admin_data.get("back_image_url"))
            == row.data[key]["image_url"]
        }
        if not adopted:
            continue
        check_images_accessible(adopted)
        image_origins(db, row, card, actor, adopted)
        row.status, row.result, row.handler_id = "PROCESSED", "INCLUDED", actor.id
        row.public_note = "提交图片已采用，小卡已正式发布，感谢你的贡献。"
        event(db, row, row.public_note)
        catalog.audit(
            db,
            actor,
            "feedback.publish_from_editor",
            "feedback",
            row.id,
            None,
            {"card_id": card.id, "result": "INCLUDED"},
        )


def credits(db, card_id):
    rows = db.scalars(
        select(CardContribution)
        .where(CardContribution.card_id == card_id)
        .order_by(CardContribution.created_at)
    ).all()
    users = {}
    for row in rows:
        user = db.get(User, row.user_id)
        version = db.get(CardImageVersion, row.image_version_id)
        users.setdefault(
            row.user_id,
            {
                "user_id": row.user_id if user and user.is_active else None,
                "name": user.display_name if user and user.is_active else "已注销用户",
                "profile_available": bool(user and user.is_active),
                "included_at": row.created_at.isoformat(),
                "source_type": "USER_SUBMITTED",
                "copyright_status": version.data.get("copyright_status", "UNKNOWN")
                if version
                else "UNKNOWN",
            },
        )
    return list(users.values())


def contributions(db, user_id, offset, limit):
    user = db.get(User, user_id)
    if not user or not user.is_active:
        raise DomainError("USER_NOT_FOUND", "用户不可用", 404)
    cards = (
        select(CardContribution.card_id)
        .join(Card, Card.id == CardContribution.card_id)
        .where(CardContribution.user_id == user_id, Card.status == "PUBLISHED")
        .group_by(CardContribution.card_id)
    )
    from sqlalchemy import func

    cards = cards.order_by(func.min(CardContribution.created_at).desc(), CardContribution.card_id)
    all_ids = db.scalars(cards).all()
    items = []
    for card_id in all_ids[offset : offset + limit]:
        first = db.scalar(
            select(CardContribution)
            .where(CardContribution.user_id == user_id, CardContribution.card_id == card_id)
            .order_by(CardContribution.created_at)
        )
        items.append(
            {
                "card": card_payload(db, db.get(Card, card_id)),
                "included_at": first.created_at.isoformat(),
            }
        )
    return {
        "items": items,
        "total": len(all_ids),
        "next_offset": offset + limit if len(all_ids) > offset + limit else None,
    }
