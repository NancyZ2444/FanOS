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
    content = submission_content(db, user, body)
    row = Feedback(
        user_id=user.id,
        request_key=body.request_key,
        kind=body.kind,
        entity_type=body.entity_type if body.kind in {"CORRECTION", "MISSING_CATALOG"} else "cards",
        entity_id=body.entity_id if body.kind == "CORRECTION" else "",
        data=content,
        history=[{"at": now(), "status": "PENDING", "result": "PENDING", "note": "已收到反馈"}],
    )
    db.add(row)
    db.flush()
    return row


def submission_content(db, user, body):
    evidence = [{"id": i, "image_url": image_for(db, user, i).image_url} for i in body.evidence_ids]
    content = {
        "request_hash": digest(body.model_dump()),
        "notes": body.notes,
        "evidence": evidence,
        "links": body.links,
    }
    if body.kind == "MISSING_CATALOG":
        from app.modules.feedback.missing_catalog import submission

        content.update(submission(db, user, body))
    elif body.kind == "CORRECTION":
        obj = description(db, body.entity_type, body.entity_id)
        if body.object_version != obj["version"]:
            raise DomainError("OBJECT_CHANGED", "资料已更新，请刷新字段后重新核对", 409)
        by_key = {f["key"]: f for f in obj["fields"]}
        if not body.fields or len({f.key for f in body.fields}) != len(body.fields):
            raise DomainError("FIELDS_REQUIRED", "请选择至少一个不重复的问题字段", 422)
        details = []
        for field_index, change in enumerate(body.fields):
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
                    try:
                        validate_value(db, field, proposed)
                    except DomainError as exc:
                        exc.details = [
                            {
                                "loc": ["body", "fields", field_index, "value"],
                                "field": change.key,
                                "msg": exc.message,
                            }
                        ]
                        raise
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
        if obj.get("profile"):
            if not body.notes.strip():
                raise DomainError("REASON_REQUIRED", "请填写修订说明及可核实出处", 422)
            for detail in details:
                if detail["mode"] == "CLEAR" and not detail["reason"].strip():
                    raise DomainError("REASON_REQUIRED", "清空资料须逐项填写原因", 422)
            pending = db.scalars(
                select(Feedback).where(
                    Feedback.user_id == user.id,
                    Feedback.entity_type == body.entity_type,
                    Feedback.entity_id == body.entity_id,
                    Feedback.result == "PENDING",
                )
            ).all()
            from app.modules.catalog.profiles import overlapping_suggestions

            if any(overlapping_suggestions(details, r.data.get("fields", [])) for r in pending):
                raise DomainError("PROFILE_PENDING", "这些字段已有待处理建议，请先查看原反馈", 409)
        content.update(
            object=obj,
            fields=details,
            profile=bool(obj.get("profile")),
            contributor_name=user.display_name,
        )
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

        scan_clue = values.get("feedback_mode") == "SCAN_CLUE"
        if not scan_clue and (
            not values.get("group_id")
            or not values.get("is_group_pc")
            and not values.get("idol_id")
        ):
            raise DomainError("ACTOR_REQUIRED", "请选择组合及艺人，团体小卡可免选艺人", 422)
        _validate_feedback_actors(db, values.get("group_id"), values.get("idol_id"))
        source_type = values.get("source_entity_type")
        if source_type not in {"ALBUM", "EVENT", "OTHER"} and not (
            scan_clue and source_type is None
        ):
            raise DomainError("SOURCE_REQUIRED", "请选择专辑、活动或其他来源", 422)
        if values.get("source_version_id") and not values.get("source_entity_id"):
            raise DomainError("SOURCE_REQUIRED", "请先选择版本对应的来源", 422)
        if values.get("source_entity_id"):
            if source_type not in {"ALBUM", "EVENT", "OTHER"}:
                raise DomainError("SOURCE_REQUIRED", "请选择对应来源类型", 422)
            resolved = _validate_source_reference(
                db,
                {
                    **values,
                    "source_mode": "KNOWN",
                    "source": {"ALBUM": "专辑", "EVENT": "活动", "OTHER": "其他"}[source_type],
                },
            )
            values.update(resolved)
        elif not scan_clue and not str(values.get("missing_source_name", "")).strip():
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
            "feedback_mode",
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
    return content


def profiles_relation_conflict(field, latest, operations):
    old = {r["id"]: r for r in field["current"]}
    current = {r["id"]: r for r in latest}
    return any(op.get("id") and old.get(op["id"]) != current.get(op["id"]) for op in operations)


def resubmit(db, row, user, body):
    lock_user(db, user)
    db.refresh(row)
    signature = digest(body.model_dump())
    retries = row.review.get("resubmission_requests", {})
    if body.request_key in retries:
        if retries[body.request_key] != signature:
            raise DomainError("IDEMPOTENCY_CONFLICT", "同一请求编号不能提交不同内容", 409)
        return row
    if body.revision != row.revision:
        raise DomainError("FEEDBACK_CHANGED", "反馈已更新，请刷新后重新补充", 409)
    if body.kind != row.kind:
        raise DomainError("INVALID_ACTION", "请补充原反馈类型的资料", 422)
    if row.result != "NEEDS_INFO":
        raise DomainError("FEEDBACK_NOT_WAITING", "当前反馈无需补充资料，请查看最新处理结果", 409)
    if row.kind != "MISSING_CARD" and (
        body.entity_type != row.entity_type
        or (row.kind == "CORRECTION" and body.entity_id != row.entity_id)
    ):
        raise DomainError("OBJECT_CHANGED", "请针对原对象补充资料", 422)
    for key in ("scan_session_id", "detected_card_id") if row.kind == "MISSING_CARD" else ():
        if body.missing.get(key) != row.data.get("scan", {}).get(key):
            raise DomainError("SCAN_CHANGED", "请针对原扫描记录补充资料", 422)
    content = submission_content(db, user, body)
    previous = [
        *row.data.get("previous_submissions", []),
        {
            "at": now(),
            "requested_note": row.public_note,
            "submission": {
                k: v
                for k, v in row.data.items()
                if k not in {"request_hash", "previous_submissions"}
            },
        },
    ]
    # The original request key/hash must stay valid if an initial submission is retried.
    row.data = {
        **content,
        "request_hash": row.data["request_hash"],
        "previous_submissions": previous,
    }
    row.review = {
        **{
            k: v
            for k, v in row.review.items()
            if k
            not in {
                "retry_changes",
                "decisions",
                "object_version",
                "public_note_draft",
                "review_decision",
                "review_decision_draft",
                "approved_payload",
                "submitted_payload",
                "approval_target_version",
                "public_decision",
                "catalog_draft",
            }
        },
        **(
            {
                "previous_catalog_drafts": [
                    *row.review.get("previous_catalog_drafts", []),
                    row.review["catalog_draft"],
                ]
            }
            if row.review.get("catalog_draft")
            else {}
        ),
        "submission_changed": True,
        "resubmission_requests": {**retries, body.request_key: signature},
    }
    row.status = "PENDING"
    row.result = "PENDING"
    row.public_note = ""
    row.handler_id = None
    event(db, row, "已补充信息，等待重新审核", action="resubmit", notify=False)
    db.flush()
    return row


PUBLIC_RESULTS = {"INCLUDED", "NOT_INCLUDED", "NEEDS_INFO"}


def accepted(row):
    return row.result == "PENDING" and row.review.get("review_decision") == "ACCEPTED"


def publicly_accepted(row):
    return row.result == "PENDING" and row.review.get("public_decision") == "ACCEPTED"


def label(row, *, admin=False):
    if accepted(row) if admin else publicly_accepted(row):
        return "已采纳，待发布"
    if row.data.get("profile") and row.result in {"INCLUDED", "NOT_INCLUDED", "NEEDS_INFO"}:
        return {
            "INCLUDED": "已收录",
            "NOT_INCLUDED": "已处理 · 未采用",
            "NEEDS_INFO": "待补充信息",
        }[row.result]
    if row.result == "INCLUDED":
        return "已采用"
    if row.result == "NOT_INCLUDED":
        return "无法采用"
    if row.result == "NEEDS_INFO":
        return "信息缺失待补充"
    if not admin:
        return "待处理"
    return {"PENDING": "待处理", "PROCESSING": "处理中", "PROCESSED": "已处理"}[row.status]


def public_history(row):
    # Older releases put draft saves and failed validation into the public timeline.
    # Preserve those entries for operators, but never expose them as user updates.
    return [
        item
        for index, item in enumerate(row.history or [])
        if item.get("visibility") != "INTERNAL"
        and (
            index == 0
            or item.get("result") in PUBLIC_RESULTS
            or item.get("action") in {"resubmit", "decide"}
        )
    ]


def payload(db, row, admin=False):
    obj = row.data.get("object", {})
    available = False
    if row.entity_id:
        try:
            target(db, row.entity_type, row.entity_id)
            available = True
        except DomainError:
            pass
    history = public_history(row)
    decisions = row.review.get("decisions", []) if admin or row.result in PUBLIC_RESULTS else []
    public_updated_at = history[-1]["at"] if history else row.created_at.isoformat()
    result = {
        "id": row.id,
        "kind": row.kind,
        "entity_type": row.entity_type,
        "entity_id": row.entity_id if admin or available else "",
        "status": row.status if admin or row.result in PUBLIC_RESULTS else "PENDING",
        "result": row.result,
        "status_label": label(row, admin=admin),
        "revision": row.revision,
        "name": obj.get("name") or row.data.get("missing", {}).get("title") or "小卡缺失反馈",
        "image_url": obj.get("image_url") or row.data.get("front", {}).get("image_url"),
        "created_at": row.created_at.isoformat(),
        "updated_at": row.updated_at.isoformat() if admin else public_updated_at,
        "public_note": row.public_note
        if row.result in PUBLIC_RESULTS or publicly_accepted(row)
        else "",
        "history": row.history if admin else history,
        "can_resubmit": row.kind in {"MISSING_CARD", "CORRECTION"} and row.result == "NEEDS_INFO",
        "profile_version": row.review.get("profile_version") if row.result == "INCLUDED" else None,
        "target_available": available,
        "submission": {k: v for k, v in row.data.items() if k != "request_hash"},
        "decisions": decisions,
    }
    if row.kind == "MISSING_CATALOG" and row.entity_type == "versions" and available:
        result["target_parent_id"] = row.review.get("catalog_draft", {}).get("album_id")
    if admin:
        user = db.get(User, row.user_id)
        result.update(
            user={"id": row.user_id, "name": user.display_name if user else "已注销用户"},
            internal_note=row.internal_note,
            handler_id=row.handler_id,
            review=row.review,
            review_decision=row.review.get("review_decision"),
            can_publish=accepted(row),
        )
        if row.kind == "MISSING_CATALOG":
            result["draft"] = row.review.get("catalog_draft")
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


def event(db, row, note, *, public=True, action=None, notify=True):
    row.revision += 1
    row.history = [
        *row.history,
        {
            "at": now(),
            "status": row.status,
            "result": row.result,
            "note": note,
            "visibility": "PUBLIC" if public else "INTERNAL",
            **({"action": action} if action else {}),
            **(
                {"review_decision": row.review.get("review_decision")} if action == "decide" else {}
            ),
        },
    ]
    if public and notify and (row.result in PUBLIC_RESULTS or action == "decide"):
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
                    "review_decision": row.review.get("review_decision"),
                },
            )
        )


def deliver_notices(db, user_id=None):
    query = select(FeedbackNotice).where(
        FeedbackNotice.delivered.is_(False),
        (
            FeedbackNotice.data["result"].as_string().in_(PUBLIC_RESULTS)
            | (FeedbackNotice.data["review_decision"].as_string() == "ACCEPTED")
        ),
    )
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
    if not row.entity_id or row.review.get("submission_changed"):
        source = row.data["missing"]
        current = {
            **current,
            **{k: v for k, v in source.items() if k in CardDraft.model_fields},
            "is_group_pc": bool(source.get("is_group_pc")),
            "is_double_sided": bool(source.get("is_double_sided")),
            "idol_id": source.get("idol_id"),
        }
        current["source_entity_id"] = source.get("source_entity_id")
        current["entity_version_id"] = source.get("source_version_id")
        current["version"] = source.get("source_version_name") or source.get("version") or ""
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
                "source_type": "USER_SUBMITTED",
                "copyright_status": "UNKNOWN",
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
    row.review = {
        **{k: v for k, v in row.review.items() if k != "retry_changes"},
        "submission_changed": False,
    }
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
        if row.entity_type in {"groups", "idols"} and field["key"] == "release_date":
            field = {**field, "key": "debut_date" if row.entity_type == "groups" else "birth_date"}
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
            if (
                row.entity_type in {"groups", "idols"}
                and (
                    field["current"] != latest
                    if field["type"] != "relations"
                    else profiles_relation_conflict(field, latest, value)
                )
                and decision["decision"] == "ACCEPT"
                and value != latest
            ):
                raise DomainError(
                    "PROFILE_FIELD_CONFLICT",
                    "该字段在提交后已更新，请对照最新全文并选择修改后采纳",
                    409,
                )
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
    elif row.entity_type in {"groups", "idols"}:
        from app.modules.catalog import profiles

        user = db.get(User, row.user_id)
        version = profiles.publish(
            db,
            row.entity_type,
            row.entity_id,
            changes,
            actor=actor,
            summary=body.public_note,
            expected=obj["version"],
            user=user,
            submission_id=row.id,
            adjusted=any(d["decision"] == "MODIFY" for d in actual),
            author_name=row.data.get("contributor_name"),
        )
        row.review = {**row.review, "profile_version": version.id}
    elif row.entity_type in {"companies", "versions"}:
        if adopted:
            changes["source_info"] = {
                **body.sources.get("source_info", {}),
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
        if adopted:
            changes["source_info"] = {
                **body.sources.get("source_info", {}),
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
        "publish"
        if body.action in {"decide", "publish", "reject", "match", "already_fixed", "need_info"}
        else "edit",
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
        body.action in {"decide", "reject", "match", "already_fixed", "need_info"}
        and not body.public_note.strip()
    ):
        raise DomainError("REASON_REQUIRED", "请填写面向用户的处理说明", 422)
    row.handler_id = actor.id
    if body.action != "publish":
        row.internal_note = body.internal_note
    if body.action in {"draft", "review"}:
        row.review = {
            **{
                k: v
                for k, v in row.review.items()
                if k
                not in {
                    "review_decision",
                    "approved_payload",
                    "submitted_payload",
                    "approval_target_version",
                }
            },
            "review_decision_draft": body.review_decision,
        }
    if body.action == "start":
        row.status = "PROCESSING"
    elif body.action == "review":
        if row.kind != "CORRECTION":
            raise DomainError("INVALID_ACTION", "缺失收录请保存小卡草稿", 422)
        row.review = {
            **row.review,
            "decisions": body.decisions,
            "object_version": body.object_version,
        }
        row.status = "PROCESSING"
    elif body.action == "draft":
        if row.kind == "MISSING_CATALOG":
            from app.modules.feedback.missing_catalog import save_draft

            save_draft(db, row, actor, body.changes)
        elif row.kind != "MISSING_CARD":
            raise DomainError("INVALID_ACTION", "纠错不能创建小卡", 422)
        else:
            draft_missing(db, row, actor, body.changes)
        row.status = "PROCESSING"
    elif body.action == "decide":
        if body.review_decision is None:
            raise DomainError("DECISION_REQUIRED", "请选择处理结果", 422)
        row.review = {
            **{
                k: v
                for k, v in row.review.items()
                if k
                not in {
                    "review_decision_draft",
                    "approved_payload",
                    "approval_target_version",
                }
            },
            "review_decision": body.review_decision,
            "public_decision": body.review_decision,
            "submitted_payload": {
                "changes": body.changes,
                "decisions": body.decisions or row.review.get("decisions", []),
                "object_version": body.object_version or row.review.get("object_version", ""),
                "sources": body.sources,
                "public_note": body.public_note.strip(),
            },
            "decisions": body.decisions or row.review.get("decisions", []),
            "object_version": body.object_version or row.review.get("object_version", ""),
        }
        if body.review_decision == "ACCEPTED":
            # Approval is a public review decision, not an implicit catalog write.
            # Publication must consume this exact snapshot, even from a list action.
            row.review = {
                **row.review,
                "approved_payload": row.review["submitted_payload"],
                "approval_target_version": (
                    digest(target(db, row.entity_type, row.entity_id, False)[1])
                    if row.entity_id
                    else None
                ),
            }
            row.status = "PROCESSING"
        else:
            row.status = "PROCESSED"
            row.result = "NOT_INCLUDED" if body.review_decision == "REJECTED" else "NEEDS_INFO"
    elif body.action == "need_info":
        row.status = "PROCESSED"
        row.result = "NEEDS_INFO"
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
        if not accepted(row):
            raise DomainError(
                "FEEDBACK_DECISION_REQUIRED", "请先提交已采纳的处理结果，再发布图鉴", 409
            )
        approved = row.review.get("approved_payload")
        if approved is None:
            raise DomainError("FEEDBACK_DECISION_REQUIRED", "请重新核对并提交已采纳的处理结果", 409)
        expected = row.review.get("approval_target_version")
        if expected and digest(target(db, row.entity_type, row.entity_id, False)[1]) != expected:
            raise DomainError("OBJECT_CHANGED", "图鉴内容已变化，请重新核对并提交处理结果", 409)
        # A caller cannot replace approved values through the publication endpoint.
        for key in ("changes", "decisions", "object_version", "sources"):
            value = getattr(body, key)
            if value and value != approved.get(key):
                raise DomainError(
                    "APPROVAL_CHANGED", "填写内容与已采纳结果不同，请重新提交处理结果", 409
                )
        publish_body = body.model_copy(update={"public_note": row.public_note, **approved})
        # Nested transaction ensures even publish validation failures leave no partial edits.
        with db.begin_nested(), feedback_publication(db, row.id):
            if row.kind == "MISSING_CARD":
                existing = db.get(Card, row.entity_id) if row.entity_id else None
                if existing and existing.status == "PENDING":
                    # Older drafts may already have entered the card review queue.
                    # Return them to editable state inside this same atomic publish;
                    # the approval target hash above has already checked concurrency.
                    catalog.transition_card(
                        db, actor, existing.id, "reject", "转由图鉴反馈已采纳结果统一发布"
                    )
                    if publish_body.changes.get("expected_updated_at"):
                        publish_body = publish_body.model_copy(
                            update={
                                "changes": {
                                    **publish_body.changes,
                                    "expected_updated_at": existing.updated_at.isoformat(),
                                }
                            }
                        )
                card = draft_missing(db, row, actor, publish_body.changes)
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
            elif row.kind == "MISSING_CATALOG":
                from app.modules.feedback.missing_catalog import publish

                publish(db, row, actor, publish_body.changes)
            else:
                publish_correction(db, row, actor, publish_body)
        row.status = "PROCESSED"
    else:
        raise DomainError("INVALID_ACTION", "不支持的处理操作", 422)
    if row.result in PUBLIC_RESULTS:
        row.review = {
            **row.review,
            "review_decision": {
                "INCLUDED": "ACCEPTED",
                "NOT_INCLUDED": "REJECTED",
                "NEEDS_INFO": "NEEDS_INFO",
            }[row.result],
        }
    public = row.result in PUBLIC_RESULTS or body.action == "decide"
    if public:
        row.public_note = (
            "已采纳并发布，图鉴已更新。" if body.action == "publish" else body.public_note.strip()
        )
        row.review = {k: v for k, v in row.review.items() if k != "public_note_draft"}
    else:
        row.review = {**row.review, "public_note_draft": body.public_note}
    row.action_keys = [*row.action_keys, body.request_key]
    row.review = {
        **row.review,
        "action_hashes": {**action_hashes, body.request_key: digest(body.model_dump())},
    }
    event(
        db,
        row,
        row.public_note
        if public
        else {
            "start": "已开始内部核实",
            "review": "已保存内部审核草稿",
            "draft": "已保存内部收录草稿",
        }[body.action],
        public=public,
        action=body.action,
    )
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
    """Prevent full-editor publication from bypassing a pending feedback review."""
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
        # A pending submission must go through its explicit approval/publication
        # action so a separate editor cannot publish unreviewed draft content.
        raise DomainError(
            "FEEDBACK_PUBLICATION_REQUIRED",
            "该小卡关联用户反馈，请在图鉴新增中提交已采纳结果后发布",
            409,
        )


def credits(db, card_id):
    from app.modules.feedback.credits import catalog_credits

    return catalog_credits(db, "cards", card_id)


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
