"""Published group/idol dossiers, private editorial drafts and immutable revisions.

Use the existing catalog extension store. Personal remarks and review evidence are
never part of a public snapshot. All publishing functions participate in the caller's
transaction (including feedback results and notices).
"""

from copy import deepcopy
from datetime import UTC, date, datetime
from hashlib import sha256

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.admin_models import ContentMetadata
from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_admin, optional_user
from app.models import Card, GroupMembership, IdolOfficialAccount, User
from app.modules.admin import catalog_service as catalog
from app.modules.admin.catalog_extensions import CatalogRecord

router = APIRouter(tags=["Catalog Profiles"])
SECTIONS = {"intro": "简介", "basic": "基本资料", "career": "从艺历程", "honors": "荣誉记录"}
COMMON = [
    ("name", "官方名称", "text"),
    ("name_translated", "中文名称", "text"),
    ("name_ko", "韩文名称", "text"),
    ("name_en", "英文名称", "text"),
    ("aliases", "其他别名", "list"),
    ("image_url", "图片", "image"),
    ("cover_image", "详情封面", "image"),
    ("debut_date", "出道日期", "date"),
    ("region", "地区", "text"),
    ("business_status", "活动状态", "text"),
    ("fandom_name", "粉丝名称", "text"),
    ("official_website", "官方网站", "url"),
    ("memberships", "成员经历", "relations"),
    ("company_relations", "经纪公司经历", "relations"),
    ("official_accounts", "官方账号", "relations"),
]


def fingerprint(value):
    from app.modules.feedback.fields import digest

    return digest(value)


def overlapping_suggestions(left, right):
    def identities(field):
        if field.get("mode") != "SET":
            return None
        return {
            ("existing", op["id"])
            if op.get("id")
            else (
                "new",
                str(
                    op.get("data", {}).get("target_id")
                    or (
                        op.get("data", {}).get("platform"),
                        op.get("data", {}).get("platform_account_id"),
                    )
                ),
            )
            for op in field.get("suggested", [])
        }

    for a in left:
        for b in right:
            if a["key"] != b["key"]:
                continue
            if a["type"] != "relations":
                return True
            x, y = identities(a), identities(b)
            if x is None or y is None or x.intersection(y):
                return True
    return False


def record_id(kind, entity_id, suffix):
    return "pf_" + sha256(f"{kind}/{entity_id}/{suffix}".encode()).hexdigest()[:56]


def require_target(db, kind, entity_id, public=True):
    if kind not in {"groups", "idols"}:
        raise DomainError("INVALID_PROFILE", "仅支持组合与艺人资料", 422)
    row = catalog.entity(db, kind, entity_id)
    raw = catalog.entity_payload(db, kind, row)
    if public and raw["status"] != "PUBLISHED":
        raise DomainError("OBJECT_UNAVAILABLE", "资料暂不可访问", 404)
    return row, raw


def definitions(kind):
    return [
        ("description", "简介", "long_text"),
        *COMMON,
        *(
            [
                ("real_name", "本名", "text"),
                ("birth_date", "生日", "date"),
                ("gender", "性别", "text"),
            ]
            if kind == "idols"
            else []
        ),
        ("career_text", "从艺历程", "long_text"),
        ("honors_text", "荣誉记录", "long_text"),
    ]


def section(key):
    return {"description": "intro", "career_text": "career", "honors_text": "honors"}.get(
        key, "basic"
    )


def legacy_career(row):
    return "\n\n".join(
        "\n".join(str(entry.get(k) or "") for k in ("period", "title", "subtitle") if entry.get(k))
        for entry in getattr(row, "careers", []) or []
    )


def relation_values(db, kind, entity_id):
    from app.modules.admin.catalog_memberships import membership_date_info

    members = []
    query = select(GroupMembership).where(
        (GroupMembership.group_id if kind == "groups" else GroupMembership.idol_id) == entity_id
    )
    extensions = {
        r.data.get("membership_id"): r
        for r in db.scalars(select(CatalogRecord).where(CatalogRecord.kind == "memberships"))
    }
    memberships = list(db.scalars(query.order_by(GroupMembership.start_date, GroupMembership.id)))
    membership_dates = membership_date_info(db, memberships)
    for m in memberships:
        if m.status == "void":
            continue
        ref_kind, ref_id = ("idols", m.idol_id) if kind == "groups" else ("groups", m.group_id)
        ref = db.get(catalog.MODELS[ref_kind], ref_id)
        ext = extensions.get(m.id)
        members.append(
            {
                "id": m.id,
                "target_id": ref_id,
                "target_type": ref_kind,
                "name": ref.name if ref else "资料暂不可用",
                "start_date": membership_dates[m.id]["start_date"],
                "end_date": str(m.end_date) if m.end_date else "",
                "status": m.status,
                "role": (ext.data.get("role", "") if ext else ""),
            }
        )
    companies = []
    for r in db.scalars(
        select(CatalogRecord)
        .where(
            CatalogRecord.kind == "company_relations",
            CatalogRecord.entity_type == kind,
            CatalogRecord.entity_id == entity_id,
            CatalogRecord.status != "ARCHIVED",
        )
        .order_by(CatalogRecord.id)
    ):
        company = db.get(CatalogRecord, r.data.get("company_id"))
        companies.append(
            {
                "id": r.id,
                "target_id": r.data.get("company_id"),
                "target_type": "companies",
                "name": company.data.get("name", "") if company else "资料暂不可用",
                "start_date": r.data.get("start_date", ""),
                "end_date": r.data.get("end_date", ""),
            }
        )
    accounts = [
        {
            "id": a.id,
            "platform": a.platform,
            "handle": a.handle,
            "platform_account_id": a.platform_account_id,
        }
        for a in db.scalars(
            select(IdolOfficialAccount)
            .where(
                (IdolOfficialAccount.group_id if kind == "groups" else IdolOfficialAccount.idol_id)
                == entity_id,
            )
            .order_by(IdolOfficialAccount.id)
        )
        if not db.get(CatalogRecord, record_id(kind, entity_id, f"void-account/{a.id}"))
    ]
    return {"memberships": members, "company_relations": companies, "official_accounts": accounts}


def snapshot(db, kind, entity_id, public=True):
    row, raw = require_target(db, kind, entity_id, public)
    values = {
        key: deepcopy(raw.get(key, [] if editor == "list" else ""))
        for key, _, editor in definitions(kind)
    }
    # The head and dossier use the same canonical columns, not metadata aliases.
    values["description"] = row.description if kind == "groups" else row.bio
    values["debut_date"] = row.debut_date if kind == "groups" else raw.get("debut_date", "")
    if kind == "idols":
        values["birth_date"] = row.birth_date
    values["career_text"] = raw.get("career_text", legacy_career(row))
    values.update(relation_values(db, kind, entity_id))
    return values


def display(field, value):
    if field["type"] == "relations":
        return "\n".join(
            " · ".join(
                str(v.get(k) or "")
                for k in ("name", "platform", "handle", "start_date", "end_date", "status", "role")
                if v.get(k)
            )
            for v in value or []
        )
    if isinstance(value, list):
        return " · ".join(map(str, value))
    return str(value or "")


def fields_for(kind, values):
    result = []
    for key, label, editor in definitions(kind):
        standard = (
            20000
            if key in {"career_text", "honors_text"}
            else 2000
            if key == "description"
            else 800
            if editor in {"image", "url"}
            else 180
        )
        limit = max(standard, len(str(values.get(key) or "")))
        f = {
            "key": key,
            "label": "所属组合及成员经历" if kind == "idols" and key == "memberships" else label,
            "type": editor,
            "section": section(key),
            "current": values.get(key),
            "max_length": limit,
            "clearable": key != "name" and editor != "relations",
        }
        f["current_display"] = display(f, f["current"])
        result.append(f)
    return result


def latest(db, kind, entity_id):
    rows = db.scalars(
        select(CatalogRecord).where(
            CatalogRecord.kind == "profile_versions",
            CatalogRecord.entity_type == kind,
            CatalogRecord.entity_id == entity_id,
        )
    ).all()
    return max(rows, key=lambda r: r.data["version"], default=None)


def editor_definition(db, kind, entity_id):
    values = snapshot(db, kind, entity_id)
    version = latest(db, kind, entity_id)
    return {
        "entity_type": kind,
        "entity_id": entity_id,
        "name": values.get("name_translated") or values["name"],
        "image_url": values["image_url"],
        "fields": [
            {**f, "entity_type": kind, "entity_id": entity_id} for f in fields_for(kind, values)
        ],
        "version": fingerprint(values),
        "profile_revision": version.data["version"] if version else 1,
        "profile": True,
    }


def append_version(
    db,
    kind,
    entity_id,
    before,
    after,
    *,
    source="PLATFORM",
    summary="资料更新",
    user=None,
    submission_id=None,
    adjusted=False,
    initial=False,
    author_name=None,
):
    previous = latest(db, kind, entity_id)
    changes = [
        {
            "key": key,
            "label": label,
            "section": section(key),
            "type": editor,
            "before": deepcopy(before.get(key)),
            "after": deepcopy(after.get(key)),
            "before_display": display({"type": editor}, before.get(key)),
            "after_display": display({"type": editor}, after.get(key)),
        }
        for key, label, editor in definitions(kind)
        if before.get(key) != after.get(key)
    ]
    if not changes and not initial:
        return previous
    version = previous.data["version"] + 1 if previous else 1
    record = CatalogRecord(
        id=record_id(kind, entity_id, str(version)),
        kind="profile_versions",
        entity_type=kind,
        entity_id=entity_id,
        status="PUBLISHED",
        data={
            "version": version,
            "parent_version": version - 1 if previous else None,
            "snapshot": deepcopy(after),
            "changes": changes,
            "source": source,
            "visibility": "PUBLIC" if source == "USER" else "INTERNAL",
            "summary": summary,
            "published_at": datetime.now(UTC).isoformat(),
            "submission_id": submission_id,
            "author": {
                "id": user.id if isinstance(user, User) else None,
                "name": (author_name or user.display_name)
                if user
                else "系统整理"
                if initial
                else "Fan OS 编辑",
            },
            "platform_adjusted": adjusted,
        },
    )
    db.add(record)
    db.flush()
    return record


def initialize(db, kind, entity_id):
    existing = latest(db, kind, entity_id)
    if existing:
        return existing
    values = snapshot(db, kind, entity_id)
    row, _ = require_target(db, kind, entity_id)
    record = append_version(
        db, kind, entity_id, {}, values, source="INITIAL", summary="历史资料初始化", initial=True
    )
    # Preserve the original structured career as internal migration evidence only.
    record.data = {
        **record.data,
        "legacy_careers": deepcopy(getattr(row, "careers", [])),
        "original_updated_at": row.updated_at.isoformat(),
    }
    return record


def validate_field(db, kind, entity_id, field, value):
    key = field["key"]
    if field["type"] == "relations":
        validate_relations(db, kind, entity_id, key, value)
        return
    if value in (None, "", []):
        if key == "name":
            raise DomainError("NAME_REQUIRED", "官方名称不能为空", 422)
        return
    if field["type"] == "list":
        if (
            not isinstance(value, list)
            or len(value) > 30
            or any(not isinstance(v, str) or not v.strip() or len(v) > 120 for v in value)
        ):
            raise DomainError("INVALID_VALUE", "别名最多30项，每项1–120字", 422)
        return
    if not isinstance(value, str) or len(value) > field["max_length"]:
        raise DomainError("INVALID_VALUE", f"{field['label']}最多{field['max_length']}字", 422)
    if field["type"] == "date":
        try:
            if date.fromisoformat(value).isoformat() != value:
                raise ValueError()
        except ValueError as exc:
            raise DomainError("INVALID_DATE", "请填写完整日期 YYYY-MM-DD，未知请留空", 422) from exc
    if field["type"] in {"image", "url"} and not value.startswith(
        ("http://", "https://", "/media/")
    ):
        raise DomainError("INVALID_URL", "请使用有效的 HTTP(S) 地址", 422)


def validate_relations(db, kind, entity_id, key, operations):
    if not isinstance(operations, list) or not operations or len(operations) > 20:
        raise DomainError("RELATION_REQUIRED", "请提交1–20项关系变更", 422)
    current = {r["id"]: r for r in relation_values(db, kind, entity_id)[key]}
    seen = set()
    accounts_seen = set()
    for op in operations:
        if not isinstance(op, dict) or op.get("operation") not in {"ADD", "UPDATE", "DELETE"}:
            raise DomainError("INVALID_RELATION", "请选择新增、修改或作废关系", 422)
        rid = op.get("id")
        if op["operation"] == "ADD" and rid:
            raise DomainError("INVALID_RELATION", "新增关系不能指定已有关系 ID", 422)
        if op["operation"] != "ADD":
            if rid not in current or rid in seen:
                raise DomainError("RELATION_CHANGED", "关系不存在、重复或已作废，请刷新", 409)
            seen.add(rid)
        if op["operation"] == "DELETE":
            if not str(op.get("reason", "")).strip():
                raise DomainError(
                    "REASON_REQUIRED", "作废关系须说明原因；正常退出请修改结束日期", 422
                )
            continue
        data = op.get("data", {})
        if not isinstance(data, dict):
            raise DomainError("INVALID_RELATION", "关系格式无效", 422)
        if key == "official_accounts":
            if set(data) - {"platform", "handle", "platform_account_id"} or any(
                not isinstance(data.get(k), str) or not 0 < len(data[k]) <= 120
                for k in ("platform", "handle", "platform_account_id")
            ):
                raise DomainError(
                    "INVALID_ACCOUNT", "请填写平台、显示名称和账号标识，不能修改认证或同步设置", 422
                )
            identity = (data["platform"], data["platform_account_id"])
            duplicate = db.scalar(
                select(IdolOfficialAccount).where(
                    IdolOfficialAccount.platform == identity[0],
                    IdolOfficialAccount.platform_account_id == identity[1],
                    IdolOfficialAccount.id != (rid or ""),
                )
            )
            if duplicate or identity in accounts_seen:
                raise DomainError("ACCOUNT_EXISTS", "该平台账号已有关联，请核对后修改已有记录", 409)
            accounts_seen.add(identity)
        else:
            if set(data) - {"target_id", "start_date", "end_date", "status", "role"}:
                raise DomainError("INVALID_RELATION", "不支持的关系字段", 422)
            target_kind = (
                "companies"
                if key == "company_relations"
                else "idols"
                if kind == "groups"
                else "groups"
            )
            from app.modules.feedback.fields import target

            target(db, target_kind, data.get("target_id"), published=target_kind != "companies")
            if key == "company_relations" and not rid:
                from app.modules.admin.catalog_companies import company_enabled

                if not company_enabled(db.get(CatalogRecord, data.get("target_id"))):
                    raise DomainError("COMPANY_DISABLED", "公司未开启，不能新增关联", 422)
            if rid and data.get("target_id") != current[rid]["target_id"]:
                raise DomainError(
                    "HISTORY_IMMUTABLE", "已有经历不能改换关联对象，请新增一段经历", 422
                )
            if key == "memberships" and data.get("start_date"):
                duplicate = db.scalar(
                    select(GroupMembership).where(
                        GroupMembership.group_id
                        == (entity_id if kind == "groups" else data["target_id"]),
                        GroupMembership.idol_id
                        == (entity_id if kind == "idols" else data["target_id"]),
                        GroupMembership.start_date == data["start_date"],
                        GroupMembership.id != (rid or ""),
                    )
                )
                if duplicate:
                    raise DomainError(
                        "MEMBERSHIP_EXISTS", "同一开始日期的经历已存在，请修订原记录", 409
                    )
            for k in ("start_date", "end_date"):
                if data.get(k):
                    try:
                        date.fromisoformat(data[k])
                    except (ValueError, TypeError) as exc:
                        raise DomainError("INVALID_DATE", "日期格式为YYYY-MM-DD", 422) from exc
            if data.get("end_date") and data.get("start_date", "") > data["end_date"]:
                raise DomainError("INVALID_RANGE", "结束日期不能早于开始日期", 422)
            if key == "memberships" and (
                not data.get("start_date")
                or data.get("status") not in {"active", "inactive", "former"}
                or (data.get("status") == "former") != bool(data.get("end_date"))
            ):
                raise DomainError(
                    "INVALID_MEMBERSHIP",
                    "请填写加入日期；历史成员须有退出日期，当前成员不填写退出日期",
                    422,
                )


def apply_relations(db, kind, entity_id, key, operations):
    from app.models import new_id

    for op in operations:
        data = op.get("data", {})
        deleting = op["operation"] == "DELETE"
        if key == "memberships":
            m = (
                db.get(GroupMembership, op.get("id"))
                if op.get("id")
                else GroupMembership(
                    id=new_id("gm"),
                    group_id=entity_id if kind == "groups" else data["target_id"],
                    idol_id=entity_id if kind == "idols" else data["target_id"],
                )
            )
            cards = db.scalars(
                select(Card).where(
                    Card.idol_id == m.idol_id,
                    Card.group_id == m.group_id,
                    Card.status != "ARCHIVED",
                )
            ).all()
            if deleting and cards:
                raise DomainError(
                    "HISTORY_PROTECTED",
                    f"该关系关联{len(cards)}张小卡，请先核实历史归属；不能直接作废",
                    409,
                )
            if not deleting:
                from app.modules.admin.catalog_memberships import membership_covers_release

                for c in cards if op.get("id") else []:
                    if c.release_date and not membership_covers_release(
                        db, m, date.fromisoformat(c.release_date.replace(".", "-"))
                    ):
                        continue
                    if c.release_date and (
                        c.release_date < data["start_date"]
                        or (data.get("end_date") and c.release_date > data["end_date"])
                    ):
                        raise DomainError(
                            "HISTORY_PROTECTED", "修改后的有效期不能排除已关联小卡的发行日期", 409
                        )
                m.start_date = date.fromisoformat(data["start_date"])
                m.end_date = date.fromisoformat(data["end_date"]) if data.get("end_date") else None
            m.status = "void" if deleting else data["status"]
            db.add(m)
            ext = next(
                (
                    r
                    for r in db.scalars(
                        select(CatalogRecord).where(CatalogRecord.kind == "memberships")
                    )
                    if r.data.get("membership_id") == m.id
                ),
                None,
            )
            if not ext:
                ext = CatalogRecord(
                    kind="memberships", entity_type="idols", entity_id=m.idol_id, data={}
                )
                db.add(ext)
            ext.status = "ARCHIVED" if deleting else "DRAFT"
            ext.data = {
                **ext.data,
                **data,
                "group_id": m.group_id,
                "membership_id": m.id,
                "status": m.status,
                "void_reason": op.get("reason", ""),
            }
        elif key == "company_relations":
            r = (
                db.get(CatalogRecord, op.get("id"))
                if op.get("id")
                else CatalogRecord(kind=key, entity_type=kind, entity_id=entity_id, data={})
            )
            r.status = "ARCHIVED" if deleting else "DRAFT"
            r.data = {
                **r.data,
                **data,
                **({"company_id": data["target_id"]} if not deleting else {}),
                "void_reason": op.get("reason", ""),
            }
            db.add(r)
        else:
            r = (
                db.get(IdolOfficialAccount, op.get("id"))
                if op.get("id")
                else IdolOfficialAccount(
                    **{("group_id" if kind == "groups" else "idol_id"): entity_id}
                )
            )
            if deleting:
                r.is_active = False
                db.add(
                    CatalogRecord(
                        id=record_id(kind, entity_id, f"void-account/{r.id}"),
                        kind="profile_void_accounts",
                        entity_type=kind,
                        entity_id=entity_id,
                        data={"reason": op["reason"]},
                    )
                )
            else:
                for k in ("platform", "handle", "platform_account_id"):
                    setattr(r, k, data[k])
                if not op.get("id"):
                    r.is_active = False  # Editorial identity suggestions never enable crawling.
            db.add(r)
    db.flush()


def publish(
    db,
    kind,
    entity_id,
    changes,
    *,
    actor,
    summary,
    expected,
    user=None,
    submission_id=None,
    adjusted=False,
    author_name=None,
):
    catalog.permit(actor, "catalog", "publish")
    row, _ = require_target(db, kind, entity_id)
    db.execute(
        update(type(row)).where(type(row).id == row.id).values(updated_at=type(row).updated_at)
    )
    db.refresh(row)
    before = snapshot(db, kind, entity_id)
    if expected != fingerprint(before):
        raise DomainError("OBJECT_CHANGED", "资料已变化，请重新核对当前正式值后发布", 409)
    if (user is not None or submission_id is not None) and not summary.strip():
        raise DomainError("REASON_REQUIRED", "请填写公开修订说明", 422)
    fields = {f["key"]: f for f in fields_for(kind, before)}
    if set(changes) - set(fields):
        raise DomainError("INVALID_FIELD", "不能修改系统记录", 422)
    affected = {(kind, entity_id): before}
    for key, value in changes.items():
        validate_field(db, kind, entity_id, fields[key], value)
        if key == "memberships":
            current = {v["id"]: v for v in before[key]}
            for op in value:
                target_id = (op.get("data") or {}).get("target_id") or current.get(
                    op.get("id"), {}
                ).get("target_id")
                other = ("idols" if kind == "groups" else "groups", target_id)
                affected[other] = snapshot(db, *other)
    for target in affected:
        initialize(db, *target)
    meta = catalog.meta_for(db, kind, entity_id)
    if meta is None:
        meta = ContentMetadata(
            entity_type=kind, entity_id=entity_id, status="PUBLISHED", operator_id=actor.id, data={}
        )
        db.add(meta)
    meta_values = dict(meta.data)
    for key, value in changes.items():
        if fields[key]["type"] == "relations":
            apply_relations(db, kind, entity_id, key, value)
            continue
        if key == "description":
            setattr(row, "description" if kind == "groups" else "bio", value or "")
        elif hasattr(row, key):
            setattr(row, key, value or "")
        meta_values[key] = value
        if key == ("debut_date" if kind == "groups" else "birth_date"):
            meta_values["release_date"] = value
    meta.data = meta_values
    db.flush()
    if snapshot(db, kind, entity_id) == before:
        raise DomainError("UNCHANGED_VALUE", "资料没有实际变化，无需重复发布", 422)
    result = None
    for target, old in affected.items():
        new = snapshot(db, *target)
        version = append_version(
            db,
            *target,
            old,
            new,
            source="USER" if user else "PLATFORM",
            summary=summary.strip() or "内部资料更新",
            user=user,
            submission_id=submission_id,
            adjusted=adjusted,
            author_name=author_name,
        )
        if target == (kind, entity_id):
            result = version
    from app.modules.catalog.media_import import queue_images

    queue_images(db, kind, entity_id, changes)
    catalog.audit(
        db, actor, "catalog.profile.publish", kind, entity_id, before, snapshot(db, kind, entity_id)
    )
    return result


def public_version(record, *, full=True, db=None):
    data = record.data
    value = {
        k: deepcopy(data[k])
        for k in (
            "version",
            "parent_version",
            "source",
            "summary",
            "published_at",
            "author",
            "platform_adjusted",
        )
    }
    author = value["author"]
    if db is not None and author.get("id"):
        owner = db.get(User, author["id"])
        if owner is None or not owner.is_active:
            value["author"] = {
                "id": None,
                "name": "已注销用户" if owner is None else "用户暂不可用",
            }
    value["id"] = record.id
    value["sections"] = list(dict.fromkeys(c["section"] for c in data["changes"]))
    if full:
        value.update(
            snapshot=deepcopy(data["snapshot"]),
            changes=deepcopy(data["changes"]),
            fields=fields_for(record.entity_type, data["snapshot"]),
        )
    return value


@router.get("/catalog/profiles/{kind}/{entity_id}")
def get_profile(
    kind: str,
    entity_id: str,
    db: Session = Depends(get_db),
    user: User | None = Depends(optional_user),
):
    values = snapshot(db, kind, entity_id)
    version = latest(db, kind, entity_id)
    from app.modules.feedback.models import Feedback

    pending = (
        db.scalar(
            select(Feedback)
            .where(
                Feedback.user_id == user.id,
                Feedback.entity_type == kind,
                Feedback.entity_id == entity_id,
                Feedback.result.in_(["PENDING", "NEEDS_INFO"]),
            )
            .order_by(Feedback.created_at.desc())
        )
        if user
        else None
    )
    return success(
        {
            "entity_type": kind,
            "entity_id": entity_id,
            "fields": fields_for(kind, values),
            "version": fingerprint(values),
            "revision": version.data["version"] if version else 1,
            "pending_feedback_id": pending.id if pending else None,
            "published_at": version.data["published_at"] if version else None,
        }
    )


@router.get("/catalog/profiles/{kind}/{entity_id}/history")
def get_history(
    kind: str,
    entity_id: str,
    offset: int = Query(0, ge=0),
    section_key: str = "",
    db: Session = Depends(get_db),
):
    require_target(db, kind, entity_id)
    rows = db.scalars(
        select(CatalogRecord).where(
            CatalogRecord.kind == "profile_versions",
            CatalogRecord.entity_type == kind,
            CatalogRecord.entity_id == entity_id,
            CatalogRecord.status == "PUBLISHED",
        )
    ).all()
    rows = [
        r
        for r in rows
        if is_public_revision(r)
        and (not section_key or any(c["section"] == section_key for c in r.data["changes"]))
    ]
    rows.sort(key=lambda r: r.data["version"], reverse=True)
    return success(
        {
            "items": [public_version(r, full=False, db=db) for r in rows[offset : offset + 20]],
            "next_offset": offset + 20 if len(rows) > offset + 20 else None,
        }
    )


@router.get("/catalog/profiles/{kind}/{entity_id}/history/{version_id}")
def get_version(kind: str, entity_id: str, version_id: str, db: Session = Depends(get_db)):
    require_target(db, kind, entity_id)
    row = db.get(CatalogRecord, version_id)
    if (
        not row
        or row.kind != "profile_versions"
        or row.entity_type != kind
        or row.entity_id != entity_id
        or row.status != "PUBLISHED"
        or not is_public_revision(row)
    ):
        raise DomainError("VERSION_NOT_FOUND", "修订记录不存在或不可访问", 404)
    return success(public_version(row, db=db))


def is_public_revision(record):
    # Legacy platform notes were public by accident; keep them in the admin archive.
    return record.data.get("source") == "USER" and record.data.get("visibility") != "INTERNAL"


class EditorialDraft(BaseModel):
    values: dict = Field(default_factory=dict)
    expected: str
    summary: str = Field(default="", max_length=2000)
    draft_version: str = ""
    request_key: str = Field(min_length=8, max_length=100)
    image_rights_confirmed: bool = False


@router.get("/admin/console/profiles/{kind}/{entity_id}")
def admin_profile(
    kind: str, entity_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    catalog.permit(actor, "catalog")
    obj = editor_definition(db, kind, entity_id)
    draft = db.get(CatalogRecord, record_id(kind, entity_id, "draft"))
    return success(
        {
            **obj,
            "draft": draft.data if draft else None,
            "draft_version": fingerprint(draft.data) if draft else "",
        }
    )


@router.put("/admin/console/profiles/{kind}/{entity_id}/draft")
def save_draft(
    kind: str,
    entity_id: str,
    body: EditorialDraft,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    catalog.permit(actor, "catalog", "edit")
    obj = editor_definition(db, kind, entity_id)
    if body.expected != obj["version"]:
        raise DomainError("OBJECT_CHANGED", "正式资料已更新，请重新核对", 409)
    for key, value in body.values.items():
        field = next((f for f in obj["fields"] if f["key"] == key), None)
        if not field:
            raise DomainError("INVALID_FIELD", "不能修改系统记录", 422)
        validate_field(db, kind, entity_id, field, value)
    rid = record_id(kind, entity_id, "draft")
    row = db.get(CatalogRecord, rid)
    if body.draft_version != (fingerprint(row.data) if row else ""):
        raise DomainError("DRAFT_CHANGED", "审核草稿已被修改，请重新载入", 409)
    if not row:
        row = CatalogRecord(id=rid, kind="profile_drafts", entity_type=kind, entity_id=entity_id)
        db.add(row)
    row.data = body.model_dump(exclude={"draft_version"})
    db.commit()
    return admin_profile(kind, entity_id, actor, db)


@router.post("/admin/console/profiles/{kind}/{entity_id}/publish")
def publish_draft(
    kind: str,
    entity_id: str,
    body: EditorialDraft,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    catalog.permit(actor, "catalog", "publish")
    # Idempotency ledger is private and tied to the same payload and actor.
    rid = record_id(kind, entity_id, f"request/{actor.id}/{body.request_key}")
    done = db.get(CatalogRecord, rid)
    signature = fingerprint(body.model_dump())
    if done:
        if done.data["signature"] != signature:
            raise DomainError("IDEMPOTENCY_CONFLICT", "同一请求不能发布不同内容", 409)
        return success(done.data["result"])
    version = publish(
        db, kind, entity_id, body.values, actor=actor, summary=body.summary, expected=body.expected
    )
    result = public_version(version)
    db.add(
        CatalogRecord(
            id=rid,
            kind="profile_publish_requests",
            entity_type=kind,
            entity_id=entity_id,
            data={"signature": signature, "result": result},
        )
    )
    draft = db.get(CatalogRecord, record_id(kind, entity_id, "draft"))
    if draft and body.draft_version == fingerprint(draft.data):
        db.delete(draft)
    db.commit()
    return success(result)


@router.get("/admin/console/profiles/{kind}/{entity_id}/history")
def admin_history(
    kind: str,
    entity_id: str,
    offset: int = Query(0, ge=0),
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    catalog.permit(actor, "catalog")
    require_target(db, kind, entity_id)
    rows = list(
        db.scalars(
            select(CatalogRecord).where(
                CatalogRecord.kind == "profile_versions",
                CatalogRecord.entity_type == kind,
                CatalogRecord.entity_id == entity_id,
                CatalogRecord.status == "PUBLISHED",
            )
        )
    )
    rows.sort(key=lambda r: r.data["version"], reverse=True)
    return success(
        {
            "items": [
                {
                    **public_version(r, full=False, db=db),
                    "visibility": "PUBLIC" if is_public_revision(r) else "INTERNAL",
                }
                for r in rows[offset : offset + 20]
            ],
            "next_offset": offset + 20 if len(rows) > offset + 20 else None,
        }
    )


@router.get("/admin/console/profiles/{kind}/{entity_id}/history/{version_id}")
def admin_version(
    kind: str,
    entity_id: str,
    version_id: str,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    catalog.permit(actor, "catalog")
    require_target(db, kind, entity_id)
    row = db.get(CatalogRecord, version_id)
    if (
        not row
        or row.kind != "profile_versions"
        or row.entity_type != kind
        or row.entity_id != entity_id
        or row.status != "PUBLISHED"
    ):
        raise DomainError("VERSION_NOT_FOUND", "修订记录不存在或不可访问", 404)
    return success(
        {
            **public_version(row, db=db),
            "visibility": "PUBLIC" if is_public_revision(row) else "INTERNAL",
        }
    )
