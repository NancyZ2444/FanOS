from __future__ import annotations

from datetime import date

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.admin_models import CardImageVersion, ContentMetadata
from app.common.events import enqueue_outbox
from app.common.response import DomainError
from app.common.serializers import card_payload
from app.future_models import (
    CommunityModerationCase,
    CommunityPost,
    CommunityReaction,
    NotificationInboxItem,
)
from app.models import (
    AlbumCard,
    Card,
    CatalogAlbum,
    CatalogEvent,
    DailyCardDraw,
    DetectedCard,
    Group,
    GroupMembership,
    Idol,
    IdolOfficialAccount,
    OperationLog,
    Report,
    ScanCandidate,
    ScanFeedback,
    SocialPost,
    User,
    UserCollectionItem,
    UserIdol,
    UserWishlistItem,
    new_id,
)
from app.modules.admin.console_schemas import CardDraft, EntityDraft
from app.modules.catalog.tags import TAG_TYPES, bind_tags, entity_tags
from app.modules.catalog.taxonomy_models import CatalogOther, CatalogTagBinding

MODELS = {
    "groups": Group,
    "idols": Idol,
    "albums": CatalogAlbum,
    "events": CatalogEvent,
    "others": CatalogOther,
}
SOURCE_KINDS = {
    "ALBUM": "albums",
    "EVENT": "events",
    "OTHER": "others",
}
TRANSITIONS = {
    "submit": ({"DRAFT", "REJECTED", "OFFLINE"}, "PENDING"),
    "publish": ({"PENDING"}, "PUBLISHED"),
    "offline": ({"PUBLISHED"}, "OFFLINE"),
    "reject": ({"PENDING"}, "REJECTED"),
    "archive": ({"DRAFT", "REJECTED", "OFFLINE"}, "ARCHIVED"),
    "restore": ({"ARCHIVED"}, "DRAFT"),
}


def permit(actor: User, domain: str, action: str = "view") -> None:
    if actor.role == "admin":
        return
    allowed = (
        {"catalog", "social", "sources"}
        if actor.role == "content_operator"
        else {"daily", "notifications", "announcements", "users", "comments", "reports"}
    )
    if domain not in allowed or (
        actor.role == "content_operator"
        and action in {"publish", "reject", "delete", "offline", "archive", "merge"}
    ):
        raise DomainError("PERMISSION_DENIED", "当前角色没有此操作权限", 403)


def audit(
    db: Session,
    actor: User,
    action: str,
    kind: str,
    item_id: str,
    before: dict | None,
    after: dict | None,
) -> None:
    db.add(
        OperationLog(
            actor_id=actor.id,
            action=action,
            target_type=kind,
            target_id=item_id,
            before=before,
            after=after,
        )
    )


def meta_for(db: Session, kind: str, item_id: str) -> ContentMetadata | None:
    return db.scalar(
        select(ContentMetadata).where(
            ContentMetadata.entity_type == kind, ContentMetadata.entity_id == item_id
        )
    )


def row_data(row) -> dict:
    result = {}
    for column in row.__table__.columns:
        value = getattr(row, column.name)
        result[column.name] = value.isoformat() if hasattr(value, "isoformat") else value
    return result


def entity(db: Session, kind: str, item_id: str):
    model = MODELS.get(kind)
    if not model:
        raise DomainError("INVALID_ENTITY_TYPE", "不支持的图鉴类型", 404)
    row = db.get(model, item_id)
    if not row:
        raise DomainError("ENTITY_NOT_FOUND", "图鉴对象不存在", 404)
    return row


def entity_payload(db: Session, kind: str, row) -> dict:
    result = row_data(row)
    meta = meta_for(db, kind, row.id)
    if meta:
        result.update(meta.data)
    if kind in TAG_TYPES:
        result.update(entity_tags(db, kind, row.id))
    result["status"] = meta.status if meta else "PUBLISHED"
    result["operator"] = meta.operator_id if meta else "系统初始化"
    if kind == "albums":
        from .album_versions import album_names

        result["versions"] = album_names(db, row)
    if kind in {"groups", "idols"}:
        result["social_count"] = (
            db.scalar(
                select(func.count())
                .select_from(IdolOfficialAccount)
                .where(
                    (IdolOfficialAccount.group_id == row.id)
                    if kind == "groups"
                    else (IdolOfficialAccount.idol_id == row.id)
                )
            )
            or 0
        )
    from .catalog_extensions import records

    company_relations = records(db, "company_relations", row.id)
    current_companies = {}
    for relation in company_relations:
        if relation.entity_type != kind:
            continue
        if (
            not relation.data.get("start_date")
            or relation.data["start_date"] <= date.today().isoformat()
        ) and (
            not relation.data.get("end_date")
            or relation.data["end_date"] >= date.today().isoformat()
        ):
            company = next(
                (c for c in records(db, "companies") if c.id == relation.data.get("company_id")),
                None,
            )
            if company:
                current_companies[company.id] = company.data["name"]
    result["company_ids"] = list(current_companies)
    if company_relations:
        result["company"] = " / ".join(current_companies.values())
    if kind == "idols":
        result["membership_history"] = [
            row_data(m)
            for m in db.scalars(
                select(GroupMembership).where(GroupMembership.idol_id == row.id)
            ).all()
        ]
        membership = db.scalar(
            select(GroupMembership).where(
                GroupMembership.idol_id == row.id,
                GroupMembership.status.in_(["active", "inactive"]),
            )
        )
        result["group_id"] = membership.group_id if membership else ""

        primary = next(
            (
                r
                for r in records(db, "memberships", row.id)
                if r.data.get("is_primary") and r.data.get("status") in {"active", "inactive"}
            ),
            None,
        )
        if primary:
            result["group_id"] = primary.data["group_id"]
        result["official_accounts"] = [
            row_data(a)
            for a in db.scalars(
                select(IdolOfficialAccount).where(IdolOfficialAccount.idol_id == row.id)
            ).all()
        ]
    if kind == "groups":
        result["member_count"] = (
            db.scalar(
                select(func.count())
                .select_from(GroupMembership)
                .where(
                    GroupMembership.group_id == row.id,
                    GroupMembership.status.in_(["active", "inactive"]),
                )
            )
            or 0
        )
    key = Card.group_id if kind == "groups" else Card.idol_id
    result["card_count"] = (
        (
            db.scalar(
                select(func.count())
                .select_from(Card)
                .where(key == row.id, Card.status != "ARCHIVED")
            )
            or 0
        )
        if kind in {"groups", "idols"}
        else sum(
            1
            for c in db.scalars(select(Card).where(Card.status != "ARCHIVED")).all()
            if c.admin_data.get("source_entity_id") == row.id
            or (
                not c.admin_data.get("source_entity_id")
                and c.source == row.name
                and c.group_id == row.group_id
            )
        )
    )
    return result


def all_entities(db: Session) -> dict:
    return {
        kind: [
            entity_payload(db, kind, row)
            for row in db.scalars(select(model).order_by(model.updated_at.desc())).all()
        ]
        for kind, model in MODELS.items()
    }


def admin_card(db: Session, card: Card) -> dict:
    result = card_payload(db, card)
    result.update(card.admin_data or {})
    # Admins retain the external original while the public payload hides pending images.
    result["image_url"] = card.image_url
    result.update(entity_tags(db, "cards", card.id))
    result["card_number"] = card.card_number
    result.update(
        status=card.status,
        created_at=card.created_at.isoformat(),
        updated_at=card.updated_at.isoformat(),
    )
    if not result.get("source_entity_id"):
        candidates = {}
        for typ, kind in SOURCE_KINDS.items():
            matches = db.scalars(
                select(MODELS[kind]).where(
                    MODELS[kind].name == card.source, MODELS[kind].group_id == card.group_id
                )
            ).all()
            for source in matches:
                candidates.setdefault(source.id, (source.id, typ))
        if len(candidates) == 1:
            source_id, source_type = next(iter(candidates.values()))
            result.update(source_entity_id=source_id, source_entity_type=source_type)
    return result


def validate_relations(
    db: Session, payload: CardDraft, complete: bool = False, existing_card: Card | None = None
) -> list[dict]:
    errors = []

    def error(field: str, message: str):
        errors.append({"field": field, "message": message})

    if not payload.group_id and not payload.idol_id:
        error("group_id", "请选择组合或独立艺人")
    elif payload.group_id and not db.get(Group, payload.group_id):
        error("group_id", "组合不存在，请重新选择组合")
    elif complete and payload.group_id:
        group_meta = meta_for(db, "groups", payload.group_id)
        if group_meta and group_meta.status != "PUBLISHED":
            error("group_id", "请先审核发布所属组合")
    if payload.idol_id:
        if not db.get(Idol, payload.idol_id):
            error("idol_id", "艺人不存在")
        membership = db.scalar(
            select(GroupMembership).where(
                GroupMembership.idol_id == payload.idol_id,
                GroupMembership.group_id == payload.group_id,
            )
        )
        # An explicit release group is a historical attribution, never rewritten
        # from the idol's present membership. Undated legacy periods are retained.
        legacy = (
            existing_card
            and existing_card.idol_id == payload.idol_id
            and existing_card.group_id == payload.group_id
            and existing_card.release_date == payload.release_date
        )
        if payload.group_id and not membership and not legacy:
            error("idol_id", "艺人不属于所选组合")
        elif payload.group_id and payload.release_date:
            try:
                released = date.fromisoformat(payload.release_date.replace(".", "-"))
                periods = db.scalars(
                    select(GroupMembership).where(
                        GroupMembership.idol_id == payload.idol_id,
                        GroupMembership.group_id == payload.group_id,
                    )
                ).all()
                if not any(
                    m.start_date <= released and (m.end_date is None or released <= m.end_date)
                    for m in periods
                ):
                    # Existing identities are not invalidated by incomplete legacy dates.
                    if not legacy:
                        error("release_date", "发行日期不在成员历史归属有效期，请补充历史关系")
            except ValueError:
                error("release_date", "发行日期格式无效")
        if complete:
            idol_meta = meta_for(db, "idols", payload.idol_id)
            if idol_meta and idol_meta.status != "PUBLISHED":
                error("idol_id", "请先审核发布所属艺人")
    elif complete and not payload.is_group_pc:
        error("idol_id", "个人卡必须选择艺人；团卡请开启团卡属性")
    if payload.source_entity_id:
        model = MODELS[SOURCE_KINDS[payload.source_entity_type]]
        source = db.get(model, payload.source_entity_id)
        from .catalog_extensions import actor_names

        artists = (
            actor_names(db, SOURCE_KINDS[payload.source_entity_type], source) if source else []
        )
        matches_artist = any(a.get("id") in {payload.group_id, payload.idol_id} for a in artists)
        if not source or (
            payload.source_entity_type != "OTHER"
            and (
                (source.group_id != payload.group_id and not matches_artist)
                or (not payload.group_id and not matches_artist)
            )
        ):
            error("source_entity_id", "来源不存在或不属于所选组合")
        elif complete:
            source_meta = meta_for(db, SOURCE_KINDS[payload.source_entity_type], source.id)
            if source_meta and source_meta.status != "PUBLISHED":
                error("source_entity_id", "请先审核发布关联来源")
    elif complete:
        error("source_entity_id", "至少关联一个专辑、活动或 Other 来源")
    if payload.entity_version_id:
        from .catalog_extensions import CatalogRecord

        version = db.get(CatalogRecord, payload.entity_version_id)
        if (
            not version
            or version.kind != "versions"
            or version.entity_type != SOURCE_KINDS[payload.source_entity_type]
            or version.entity_id != payload.source_entity_id
        ):
            error("entity_version_id", "版本不属于所选来源")
        elif version.status == "ARCHIVED" and not (
            existing_card
            and (existing_card.admin_data or {}).get("entity_version_id") == version.id
        ):
            error("entity_version_id", "归档版本不可用于新增关联")
    if complete:
        if not payload.image_url:
            error("image_url", "请上传小卡正面图片")
        if payload.is_double_sided and not payload.back_image_url:
            error("back_image_url", "双面卡必须上传背面图片")
        if payload.has_ar and not payload.ar_resource:
            error("ar_resource", "AR 卡必须填写 AR 资源地址")
        for side in ("front_source", "back_source"):
            if side == "back_source" and not payload.back_image_url:
                continue
            info = getattr(payload, side)
            if info.source_type != "USER_SUBMITTED" and not info.source_url:
                error(f"{side}.source_url", "请填写图片来源链接")
            if info.copyright_status not in {"AUTHORIZED", "OFFICIAL_SOURCE"}:
                error(f"{side}.copyright_status", "发布前请确认图片版权为已授权或官方来源")
    return errors


def fail_fields(errors: list[dict]) -> None:
    if errors:
        exc = DomainError("FIELD_VALIDATION_ERROR", errors[0]["message"], 422)
        exc.details = errors
        raise exc


def save_card(
    db: Session,
    actor: User,
    payload: CardDraft,
    card_id: str | None = None,
    *,
    tag_source="INTERNAL",
    submission_id=None,
) -> Card:
    permit(actor, "catalog", "edit")
    card = db.get(Card, card_id) if card_id else None
    fail_fields(validate_relations(db, payload, existing_card=card))
    if card_id and not card:
        raise DomainError("CARD_NOT_FOUND", "小卡不存在", 404)
    if card and card.status not in {"DRAFT", "REJECTED", "OFFLINE"}:
        raise DomainError("CARD_NOT_EDITABLE", "请先下架已发布内容，或驳回审核后再编辑", 409)
    if (
        card
        and payload.expected_updated_at
        and payload.expected_updated_at != card.updated_at.isoformat()
    ):
        raise DomainError("EDIT_CONFLICT", "内容已被其他操作更新，请刷新后再编辑", 409)
    before = admin_card(db, card) if card else None
    if payload.entity_version_id:
        from .catalog_extensions import CatalogRecord

        payload.version = db.get(CatalogRecord, payload.entity_version_id).data["name"]
    values = payload.model_dump(exclude={"expected_updated_at"})
    fields = {
        "title",
        "title_en",
        "title_ko",
        "title_translated",
        "group_id",
        "idol_id",
        "card_type",
        "version",
        "release_date",
        "region",
        "image_url",
    }
    base = {key: value for key, value in values.items() if key in fields}
    base["idol_id"] = payload.idol_id or None
    base["group_id"] = payload.group_id or None
    source = (
        db.get(MODELS[SOURCE_KINDS[payload.source_entity_type]], payload.source_entity_id)
        if payload.source_entity_id
        else None
    )
    base["source"] = source.name if source else ""
    # Labels remain compatible with existing clients; catalog editors no longer name cards.
    if not base["title"]:
        base["title"] = (
            " · ".join(v for v in (base["source"], payload.version, payload.card_type) if v)[:180]
            or "小卡"
        )
    values.pop("card_number", None)
    if card is None:
        card = Card(id=new_id("card"), status="DRAFT", **base)
        db.add(card)
    else:
        for key, value in base.items():
            setattr(card, key, value)
    card.status = "DRAFT"
    card.admin_data = {
        **(card.admin_data or {}),
        **{key: value for key, value in values.items() if key not in fields},
    }
    card.admin_data = {**card.admin_data, "operator": actor.display_name}
    card.admin_data.pop("card_number", None)
    db.flush()
    card.admin_data = {
        **card.admin_data,
        "tags": bind_tags(db, "cards", card.id, payload.tags, actor.id, tag_source, submission_id),
    }
    for side, field in [("FRONT", "image_url"), ("BACK", "back_image_url")]:
        source_key = "front_source" if side == "FRONT" else "back_source"
        snapshot = {"image_url": values[field], **values[source_key]}
        previous = db.scalar(
            select(CardImageVersion)
            .where(CardImageVersion.card_id == card.id, CardImageVersion.side == side)
            .order_by(CardImageVersion.version.desc())
        )
        if previous and previous.data.get("image_url") == snapshot["image_url"]:
            for provenance_key in (
                "version_identity",
                "submissions",
                "converted_by",
                "converted_at",
            ):
                if provenance_key in previous.data:
                    snapshot[provenance_key] = previous.data[provenance_key]
        version = previous.version if previous else 0
        if not previous and before and before.get(field):
            original = {"image_url": before[field], **before.get(source_key, {})}
            db.add(
                CardImageVersion(
                    card_id=card.id, side=side, version=1, data=original, operator_id="legacy"
                )
            )
            version = 1
        old_snapshot = (
            previous.data
            if previous
            else (
                {"image_url": before.get(field), **before.get(source_key, {})} if before else None
            )
        )
        if snapshot["image_url"] and snapshot != old_snapshot:
            db.add(
                CardImageVersion(
                    card_id=card.id,
                    side=side,
                    version=version + 1,
                    data=snapshot,
                    operator_id=actor.id,
                )
            )
    from app.modules.catalog.media_import import owned_image

    if (
        payload.image_url
        and owned_image(payload.image_url)
        and (not before or before.get("image_url") != payload.image_url)
    ):
        enqueue_outbox(
            db,
            event_type="catalog.card.image.updated",
            aggregate_type="card",
            aggregate_id=card.id,
            payload={"card_id": card.id, "image_url": payload.image_url},
        )
    audit(db, actor, "catalog.card.save", "card", card.id, before, admin_card(db, card))
    from app.modules.catalog.media_import import queue_images

    queue_images(db, "cards", card.id, {**card.admin_data, "image_url": card.image_url})
    db.flush()
    return card


def transition_card(db: Session, actor: User, card_id: str, action: str, reason: str = "") -> dict:
    permit(actor, "catalog", action)
    card = db.get(Card, card_id)
    if not card:
        raise DomainError("CARD_NOT_FOUND", "小卡不存在", 404)
    allowed, status = TRANSITIONS.get(action, (set(), ""))
    if card.status not in allowed:
        raise DomainError("INVALID_TRANSITION", f"当前状态 {card.status} 不允许执行此操作", 409)
    if action == "reject" and not reason.strip():
        raise DomainError("REASON_REQUIRED", "请填写驳回原因", 422)
    if action in {"submit", "publish"}:
        fail_fields(
            validate_relations(db, CardDraft.model_validate(admin_card(db, card)), True, card)
        )
    before = admin_card(db, card)
    card.status = status
    card.admin_data = {**card.admin_data, "review_note": reason, "operator": actor.display_name}
    if action == "publish":
        card.admin_data = {**card.admin_data, "ever_published": True}
        from app.modules.feedback.service import catalog_card_published

        catalog_card_published(db, card, actor)
    db.flush()
    result = admin_card(db, card)
    audit(db, actor, f"catalog.card.{action}", "card", card.id, before, result)
    enqueue_outbox(
        db,
        event_type=f"catalog.card.{action}",
        aggregate_type="card",
        aggregate_id=card.id,
        payload={"card_id": card.id, "status": status},
    )
    return result


def validate_event_location(payload: EntityDraft) -> None:
    if payload.is_online and not payload.platform:
        fail_fields([{"field": "platform", "message": "线上活动必须填写平台"}])
    if not payload.is_online and not payload.city:
        fail_fields([{"field": "city", "message": "线下活动必须填写城市"}])


def save_entity(
    db: Session,
    actor: User,
    kind: str,
    payload: EntityDraft,
    item_id: str | None = None,
    *,
    tag_source="INTERNAL",
    submission_id=None,
) -> dict:
    permit(actor, "catalog", "edit")
    if kind not in MODELS:
        raise DomainError("INVALID_ENTITY_TYPE", "不支持的图鉴类型", 404)
    row = entity(db, kind, item_id) if item_id else None
    before = entity_payload(db, kind, row) if row else None
    if before and before["status"] in {"PUBLISHED", "PENDING", "ARCHIVED"}:
        raise DomainError("ENTITY_NOT_EDITABLE", "请先下架或驳回后再编辑", 409)
    if kind == "idols" and before and (before.get("group_id") or "") != (payload.group_id or ""):
        fail_fields(
            [
                {
                    "field": "group_id",
                    "message": "请在成员经历中维护退团、加入和主身份，避免覆盖历史关系",
                }
            ]
        )
    if kind == "others":
        from app.modules.catalog.contributions import validate_other_fields

        validate_other_fields(payload.model_dump())
    if kind == "events":
        validate_event_location(payload)
        if payload.end_date and payload.release_date and payload.end_date < payload.release_date:
            fail_fields([{"field": "end_date", "message": "结束日期不能早于开始日期"}])
        if payload.parent_event_id:
            ancestor = db.get(CatalogEvent, payload.parent_event_id)
            seen = set()
            while ancestor:
                if ancestor.id == item_id or ancestor.id in seen:
                    fail_fields([{"field": "parent_event_id", "message": "活动层级不能形成循环"}])
                seen.add(ancestor.id)
                ancestor = (
                    db.get(CatalogEvent, ancestor.parent_event_id)
                    if ancestor.parent_event_id
                    else None
                )
            if not db.get(CatalogEvent, payload.parent_event_id):
                fail_fields([{"field": "parent_event_id", "message": "父活动不存在"}])
        if payload.album_id and not db.get(CatalogAlbum, payload.album_id):
            fail_fields([{"field": "album_id", "message": "关联专辑不存在"}])
    if payload.group_id and not db.get(Group, payload.group_id):
        fail_fields([{"field": "group_id", "message": "请选择有效组合"}])
    artists = payload.artists or (
        [{"type": "groups", "id": payload.group_id}] if payload.group_id else []
    )
    if payload.idol_id and not any(a.get("id") == payload.idol_id for a in artists):
        artists.append({"type": "idols", "id": payload.idol_id})
    for artist in artists:
        if artist.get("type") not in {"groups", "idols"} or not db.get(
            MODELS[artist["type"]], artist.get("id")
        ):
            fail_fields([{"field": "artists", "message": "艺人归属无效"}])
    if kind not in {"groups", "idols"} and not artists:
        fail_fields([{"field": "artists", "message": "请选择至少一个组合或个人艺人"}])
    if kind == "groups":
        existing = db.scalar(select(Group).where(Group.name == payload.name))
        if existing and existing.id != item_id:
            fail_fields([{"field": "name", "message": "组合名称已存在"}])
    values = payload.model_dump()
    if kind == "albums" and row is not None and "versions" not in payload.model_fields_set:
        from .album_versions import album_names

        values["versions"] = album_names(db, row)
    # Company IDs are a selection command; current IDs are always derived from history.
    values.pop("company_ids")
    values.pop("company_effective_date")
    from .catalog_companies import sync_company_selection, validate_company_selection

    validate_company_selection(db, kind, payload, before)
    if kind in {"groups", "idols"}:
        if payload.company_ids is not None:
            from .catalog_extensions import CatalogRecord

            values["company"] = " / ".join(
                db.get(CatalogRecord, cid).data["name"]
                for cid in dict.fromkeys(payload.company_ids)
            )
        elif before and before.get("company_ids"):
            values["company"] = before["company"]
        elif before and "company" not in payload.model_fields_set:
            values["company"] = row.company
    values["artists"] = artists
    columns = {c.name for c in MODELS[kind].__table__.columns}
    attrs = {k: v for k, v in values.items() if k in columns}
    if "group_id" in columns:
        attrs["group_id"] = payload.group_id or next(
            (a["id"] for a in artists if a["type"] == "groups"), None
        )
    if kind == "idols":
        attrs.update(
            bio=payload.description,
            birth_date=payload.release_date,
            initials=payload.name[:2].upper(),
        )
    if kind == "groups":
        attrs["debut_date"] = payload.release_date
    if kind in {"albums", "events"}:
        attrs["artist_name"] = " / ".join(db.get(MODELS[a["type"]], a["id"]).name for a in artists)
        attrs["is_published"] = False
        if kind == "albums":
            attrs.update(album_type=payload.type or "Mini Album")
        if kind == "events":
            attrs.update(event_type=payload.type or "Fansign", start_date=payload.release_date)
        if kind == "merchandise":
            attrs["type"] = payload.type or "Other"
    if kind == "others":
        attrs = {
            key: values[key]
            for key in ("name", "original_name", "start_date", "end_date", "description")
        }
        attrs["group_id"] = payload.group_id or next(
            (a["id"] for a in artists if a["type"] == "groups"), None
        )
        attrs["is_published"] = False
        values = {key: value for key, value in attrs.items() if key != "is_published"} | {
            "tags": values["tags"],
            "artists": artists,
            "idol_id": payload.idol_id,
            "artist_name": " / ".join(db.get(MODELS[a["type"]], a["id"]).name for a in artists),
            "image_url": payload.image_url,
        }
    if row is None:
        row = MODELS[kind](id=new_id(kind[:-1]), **attrs)
        db.add(row)
    else:
        for key, value in attrs.items():
            setattr(row, key, value)
    db.flush()
    meta = meta_for(db, kind, row.id)
    if meta is None:
        meta = ContentMetadata(
            entity_type=kind, entity_id=row.id, status="DRAFT", operator_id=actor.id
        )
        db.add(meta)
    meta.status = "DRAFT"
    meta.data = {**(meta.data or {}), **values}
    meta.operator_id = actor.id
    if kind in TAG_TYPES:
        meta.data = {
            **meta.data,
            "tags": bind_tags(db, kind, row.id, payload.tags, actor.id, tag_source, submission_id),
        }
    if kind == "idols" and before is None and payload.group_id:
        db.add(GroupMembership(group_id=payload.group_id, idol_id=row.id))
    sync_company_selection(db, actor, kind, row.id, payload, before)
    if kind == "albums":
        from .album_versions import replace_versions

        replace_versions(db, actor, row, values["versions"])
    db.flush()
    result = entity_payload(db, kind, row)
    from app.modules.catalog.media_import import queue_images

    queue_images(db, kind, row.id, result)
    audit(db, actor, "catalog.entity.save", kind, row.id, before, result)
    return result


def transition_entity(
    db: Session, actor: User, kind: str, item_id: str, action: str, reason: str = ""
) -> dict:
    permit(actor, "catalog", action)
    row = entity(db, kind, item_id)
    before = entity_payload(db, kind, row)
    allowed, target = TRANSITIONS.get(action, (set(), ""))
    if kind == "albums" and before.get("merged_into"):
        raise DomainError("ALBUM_MERGED", "该专辑已归并到父专辑，旧 ID 仅供历史查询", 409)
    if before["status"] not in allowed:
        raise DomainError("INVALID_TRANSITION", "当前状态不允许执行此操作", 409)
    if kind == "events" and action in {"submit", "publish"}:
        validate_event_location(EntityDraft.model_validate(before))
    if kind == "others" and action in {"submit", "publish"}:
        from .catalog_extensions import actor_names

        artists = actor_names(db, kind, row)
        if not artists or any(
            a.get("type") not in {"groups", "idols"} or not db.get(MODELS[a["type"]], a.get("id"))
            for a in artists
        ):
            fail_fields([{"field": "artists", "message": "请选择至少一个有效的组合或艺人"}])
    if action == "reject" and not reason.strip():
        raise DomainError("REASON_REQUIRED", "请填写驳回原因", 422)
    meta = meta_for(db, kind, item_id)
    if not meta:
        meta = ContentMetadata(entity_type=kind, entity_id=item_id, operator_id=actor.id, data={})
        db.add(meta)
    meta.status = target
    meta.operator_id = actor.id
    meta.data = {**meta.data, "review_note": reason}
    if action == "publish":
        meta.data = {**meta.data, "ever_published": True}
    if hasattr(row, "is_published"):
        row.is_published = target == "PUBLISHED"
    db.flush()
    result = entity_payload(db, kind, row)
    audit(db, actor, f"catalog.entity.{action}", kind, item_id, before, result)
    return result


def _count(db: Session, model, *conditions) -> int:
    return db.scalar(select(func.count()).select_from(model).where(*conditions)) or 0


def _contains_reference(value, item_id: str) -> bool:
    if isinstance(value, dict):
        return item_id in value or any(
            _contains_reference(child, item_id) for child in value.values()
        )
    if isinstance(value, list):
        return any(_contains_reference(child, item_id) for child in value)
    return value == item_id


def _generic_reference_counts(db: Session, item_id: str, own_kind: str | None = None) -> list[dict]:
    counts: dict[str, int] = {}

    def add(label: str, count: int) -> None:
        if count:
            counts[label] = counts.get(label, 0) + count

    metadata = db.scalars(select(ContentMetadata)).all()
    for row in metadata:
        if row.entity_type == own_kind and row.entity_id == item_id:
            continue
        if _contains_reference(row.data or {}, item_id):
            add(f"{row.entity_type} 运营配置", 1)
    add(
        "站内通知",
        sum(
            row.source_id == item_id or _contains_reference(row.payload or {}, item_id)
            for row in db.scalars(select(NotificationInboxItem)).all()
        ),
    )
    add(
        "社区内容",
        _count(db, CommunityPost, CommunityPost.subject_id == item_id)
        + _count(db, CommunityReaction, CommunityReaction.target_id == item_id),
    )
    add("举报记录", _count(db, Report, Report.target_id == item_id))
    add(
        "社区审核",
        _count(db, CommunityModerationCase, CommunityModerationCase.target_id == item_id),
    )
    add(
        "动态关联",
        sum(
            _contains_reference(post.relation or {}, item_id)
            for post in db.scalars(select(SocialPost)).all()
        ),
    )
    add(
        "反馈关联",
        sum(
            _contains_reference(feedback.payload or {}, item_id)
            for feedback in db.scalars(select(ScanFeedback)).all()
        ),
    )
    return [{"label": label, "count": count} for label, count in counts.items()]


def deletion_blockers(
    db: Session, kind: str, item_id: str, include_upstream: bool = True
) -> list[dict]:
    row = entity(db, kind, item_id) if kind != "cards" else db.get(Card, item_id)
    if not row:
        raise DomainError("CARD_NOT_FOUND", "小卡不存在", 404)
    blockers: list[dict] = []

    def add(label: str, count: int) -> None:
        if count:
            blockers.append({"label": label, "count": count})

    if kind == "groups":
        add("艺人关系", _count(db, GroupMembership, GroupMembership.group_id == item_id))
        add("官方账号", _count(db, IdolOfficialAccount, IdolOfficialAccount.group_id == item_id))
        add("小卡", _count(db, Card, Card.group_id == item_id))
        add("专辑", _count(db, CatalogAlbum, CatalogAlbum.group_id == item_id))
        add("活动", _count(db, CatalogEvent, CatalogEvent.group_id == item_id))
        add("Other 来源", _count(db, CatalogOther, CatalogOther.group_id == item_id))
        add("社交动态", _count(db, SocialPost, SocialPost.group_id == item_id))
        add("扫描反馈", _count(db, ScanFeedback, ScanFeedback.group_id == item_id))
    elif kind == "idols":
        if include_upstream:
            add("所属组合关系", _count(db, GroupMembership, GroupMembership.idol_id == item_id))
        add("官方账号", _count(db, IdolOfficialAccount, IdolOfficialAccount.idol_id == item_id))
        add("小卡", _count(db, Card, Card.idol_id == item_id))
        add("用户本命", _count(db, UserIdol, UserIdol.idol_id == item_id))
        add("社交动态", _count(db, SocialPost, SocialPost.idol_id == item_id))
        add("扫描反馈", _count(db, ScanFeedback, ScanFeedback.idol_id == item_id))
    elif kind in {"albums", "events", "others"}:
        meta = meta_for(db, kind, item_id)
        if kind == "albums" and meta and meta.data.get("merged_into"):
            add("专辑归并历史映射", 1)
        add(
            "小卡来源",
            sum(
                (card.admin_data or {}).get("source_entity_id") == item_id
                or (
                    not (card.admin_data or {}).get("source_entity_id")
                    and card.group_id == row.group_id
                    and card.source == row.name
                )
                for card in db.scalars(select(Card)).all()
            ),
        )
        if kind == "events":
            add("子活动", _count(db, CatalogEvent, CatalogEvent.parent_event_id == item_id))
    elif kind == "cards":
        add(
            "合并记录引用",
            sum(
                _contains_reference(c.admin_data or {}, item_id)
                for c in db.scalars(select(Card).where(Card.id != item_id)).all()
            ),
        )
        add("用户收藏", _count(db, UserCollectionItem, UserCollectionItem.card_id == item_id))
        add("用户心愿单", _count(db, UserWishlistItem, UserWishlistItem.card_id == item_id))
        from app.album_models import AlbumSlot
        from app.models import CardAlbum

        add(
            "数字卡册",
            _count(db, AlbumCard, AlbumCard.card_id == item_id)
            + _count(db, AlbumSlot, AlbumSlot.card_id == item_id)
            + sum(
                _contains_reference(a.cover_config, item_id)
                or _contains_reference(a.published_snapshot, item_id)
                for a in db.scalars(select(CardAlbum)).all()
            ),
        )
        add("翻卡记录", _count(db, DailyCardDraw, DailyCardDraw.card_id == item_id))
        add(
            "扫描确认",
            _count(db, DetectedCard, DetectedCard.user_confirmed_card_id == item_id),
        )
        add("扫描候选", _count(db, ScanCandidate, ScanCandidate.card_id == item_id))
        add(
            "社交动态",
            sum(
                item_id in ((post.relation or {}).get("card_ids") or [])
                for post in db.scalars(select(SocialPost)).all()
            ),
        )
    blockers.extend(_generic_reference_counts(db, item_id, kind))
    from .catalog_extensions import CatalogRecord

    for record in db.scalars(select(CatalogRecord)).all():
        if record.kind == "import_input":
            continue
        incoming = _contains_reference(record.data, item_id) and record.entity_id != item_id
        outgoing = record.entity_id == item_id and record.kind in {
            "sources",
            "company_relations",
            "memberships",
        }
        if incoming or (include_upstream and outgoing):
            add(f"{record.kind} 关联", 1)
    if not include_upstream:
        return blockers
    # Both incoming references and the record's own upstream ownership block deletion.
    if kind in TAG_TYPES:
        add(
            "标签关联",
            _count(
                db,
                CatalogTagBinding,
                CatalogTagBinding.entity_type == TAG_TYPES[kind],
                CatalogTagBinding.entity_id == item_id,
            ),
        )
    add("所属组合", int(bool(getattr(row, "group_id", None))))
    add("所属艺人", int(bool(getattr(row, "idol_id", None))))
    add("父活动", int(bool(getattr(row, "parent_event_id", None))))
    data = (
        (row.admin_data or {})
        if kind == "cards"
        else ((meta_for(db, kind, item_id).data or {}) if meta_for(db, kind, item_id) else {})
    )
    if kind != "cards":
        add("配置中的所属艺人", int(bool(data.get("idol_id"))))
        if kind == "groups":
            add("配置中的所属组合", int(bool(data.get("group_id"))))
    else:
        add("合并目标关系", int(bool(data.get("merged_into"))))
        add("发行来源", int(bool(data.get("source_entity_id") or row.source)))
        add("发行版本", int(bool(data.get("entity_version_id"))))
        add("所属批次", int(bool(data.get("batch_id"))))
    for related_kind, model in {**MODELS, "cards": Card}.items():
        references = sum(
            related_id != item_id and _contains_reference(data, related_id)
            for related_id in db.scalars(select(model.id)).all()
        )
        add(f"自身配置关联 {related_kind}", references)
    return blockers


def _raise_delete_blocked(blockers: list[dict]) -> None:
    if not blockers:
        return
    summary = "、".join(f"{item['label']} {item['count']} 条" for item in blockers[:5])
    if len(blockers) > 5:
        summary += f"等 {len(blockers)} 类数据"
    exc = DomainError("ENTITY_HAS_RELATIONS", f"无法删除，仍关联：{summary}", 409)
    exc.details = blockers
    raise exc


def delete_entity(db: Session, actor: User, kind: str, item_id: str) -> dict:
    permit(actor, "catalog", "delete")
    row = entity(db, kind, item_id)
    before = entity_payload(db, kind, row)
    if before["status"] not in {"DRAFT", "OFFLINE", "ARCHIVED"}:
        raise DomainError("DELETE_REQUIRES_ARCHIVED", "仅草稿、已下架或归档记录可删除", 409)
    published = before["status"] == "ARCHIVED" or was_published(db, kind, item_id, before)
    _raise_delete_blocked(deletion_blockers(db, kind, item_id, published))
    if kind == "idols" and not published:
        for membership in db.scalars(
            select(GroupMembership).where(GroupMembership.idol_id == item_id)
        ).all():
            db.delete(membership)
    cleanup_owned_records(db, item_id)
    meta = meta_for(db, kind, item_id)
    if meta:
        db.delete(meta)
    audit(db, actor, "catalog.entity.delete", kind, item_id, before, None)
    db.delete(row)
    db.flush()
    return {"id": item_id, "name": before["name"], "deleted": True}


def delete_card(db: Session, actor: User, card_id: str) -> dict:
    permit(actor, "catalog", "delete")
    card = db.get(Card, card_id)
    if not card:
        raise DomainError("CARD_NOT_FOUND", "小卡不存在", 404)
    before = admin_card(db, card)
    if card.status not in {"DRAFT", "OFFLINE", "ARCHIVED"}:
        raise DomainError("DELETE_REQUIRES_ARCHIVED", "仅草稿、已下架或归档小卡可删除", 409)
    _raise_delete_blocked(
        deletion_blockers(
            db,
            "cards",
            card_id,
            card.status == "ARCHIVED" or was_published(db, "cards", card_id, before),
        )
    )
    cleanup_owned_records(db, card_id)
    for version in db.scalars(
        select(CardImageVersion).where(CardImageVersion.card_id == card_id)
    ).all():
        db.delete(version)
    audit(db, actor, "catalog.card.delete", "card", card_id, before, None)
    db.delete(card)
    db.flush()
    return {"id": card_id, "title": before["title"], "deleted": True}


def was_published(db: Session, kind: str, item_id: str, data: dict) -> bool:
    if data.get("ever_published") or data.get("status") == "OFFLINE":
        return True
    logs = db.scalars(select(OperationLog).where(OperationLog.target_id == item_id)).all()
    if any(
        log.action.endswith(".publish")
        or (log.before or {}).get("status") == "PUBLISHED"
        or (log.after or {}).get("status") == "PUBLISHED"
        for log in logs
    ):
        return True
    # Unknown legacy records are protected; absence of a log is not proof of never publishing.
    return not any(log.action.endswith(".save") and log.before is None for log in logs)


def cleanup_owned_records(db: Session, item_id: str):
    from sqlalchemy import delete

    db.execute(delete(CatalogTagBinding).where(CatalogTagBinding.entity_id == item_id))
    from .catalog_extensions import CatalogRecord

    for record in db.scalars(select(CatalogRecord).where(CatalogRecord.entity_id == item_id)).all():
        if record.kind not in {"reviews"}:
            db.delete(record)
