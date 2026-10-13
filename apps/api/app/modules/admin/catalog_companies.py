"""Company selections create dated relationships without rewriting company history."""

import unicodedata
from datetime import date, timedelta

from app.common.response import DomainError

from .catalog_extensions import CatalogRecord, records


def company_name_key(name: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", name).split()).casefold()


def normalize_company_name(name: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", name).split())


def resolve_company_name(db, name: str):
    normalized = normalize_company_name(name)
    if not normalized:
        return None, "none"
    matches = [
        company
        for company in records(db, "companies")
        if company_name_key(company.data.get("name", "")) == company_name_key(normalized)
    ]
    if len(matches) > 1:
        raise DomainError(
            "COMPANY_AMBIGUOUS",
            "系统中存在多个同名公司，请先在公司管理中合并或修正",
            409,
        )
    if matches and matches[0].status == "ARCHIVED":
        raise DomainError(
            "COMPANY_ARCHIVED",
            "匹配到已归档公司，请先恢复该公司后再导入",
            409,
        )
    return (matches[0], "existing") if matches else (None, "create")


def get_or_create_company(db, actor, name: str, cache: dict | None = None):
    from .catalog_service import audit, row_data

    normalized = normalize_company_name(name)
    key = company_name_key(normalized)
    if cache is not None and key in cache:
        return cache[key], "reused"
    company, _ = resolve_company_name(db, normalized)
    if company:
        if cache is not None:
            cache[key] = company
        return company, "reused"
    company = CatalogRecord(
        kind="companies",
        data={
            "name": normalized,
            "description": "",
            "source": "groups_idols_import",
        },
    )
    db.add(company)
    db.flush()
    audit(
        db,
        actor,
        "catalog.companies.import.create",
        "companies",
        company.id,
        None,
        row_data(company),
    )
    if cache is not None:
        cache[key] = company
    return company, "created"


def relation_is_active(relation, today: str | None = None) -> bool:
    today = today or date.today().isoformat()
    return (not relation.data.get("start_date") or relation.data["start_date"] <= today) and (
        not relation.data.get("end_date") or relation.data["end_date"] >= today
    )


def active_relations(db, kind, entity_id):
    return [
        r
        for r in records(db, "company_relations", entity_id)
        if r.entity_type == kind and relation_is_active(r)
    ]


def _sync_company_text(db, kind: str, entity_id: str) -> str:
    from .catalog_service import MODELS, meta_for

    company_names = []
    seen = set()
    for relation in active_relations(db, kind, entity_id):
        company = db.get(CatalogRecord, relation.data.get("company_id"))
        if not company or company.kind != "companies" or company.id in seen:
            continue
        seen.add(company.id)
        company_names.append(company.data.get("name", ""))
    company_text = " / ".join(filter(None, company_names))
    entity = db.get(MODELS[kind], entity_id)
    if entity:
        entity.company = company_text
    metadata = meta_for(db, kind, entity_id)
    if metadata:
        metadata.data = {**metadata.data, "company": company_text}
    return company_text


def ensure_company_relation(
    db,
    actor,
    kind: str,
    entity_id: str,
    company_id: str,
    source: str = "groups_idols_import",
):
    from .catalog_service import audit, row_data

    if kind not in {"groups", "idols"}:
        raise DomainError("INVALID_ENTITY_TYPE", "公司只能关联组合或艺人", 422)
    company = db.get(CatalogRecord, company_id)
    if not company or company.kind != "companies" or company.status == "ARCHIVED":
        raise DomainError("COMPANY_NOT_FOUND", "公司不存在或已归档", 422)
    current = active_relations(db, kind, entity_id)
    existing = next(
        (relation for relation in current if relation.data.get("company_id") == company_id),
        None,
    )
    if existing:
        _sync_company_text(db, kind, entity_id)
        return existing, "existing"
    company_ids = {relation.data.get("company_id") for relation in current}
    company_ids.add(company_id)
    names = [
        item.data.get("name", "")
        for item_id in company_ids
        if item_id and (item := db.get(CatalogRecord, item_id)) and item.kind == "companies"
    ]
    if len(" / ".join(names)) > 120:
        raise DomainError("COMPANY_NAMES_TOO_LONG", "关联公司名称合计不能超过 120 字符", 422)
    relation = CatalogRecord(
        kind="company_relations",
        entity_type=kind,
        entity_id=entity_id,
        data={
            "company_id": company_id,
            "relation_type": "Agency",
            "start_date": "",
            "end_date": "",
            "date_unknown": True,
            "source": source,
        },
    )
    db.add(relation)
    db.flush()
    audit(
        db,
        actor,
        "catalog.company_relations.import",
        "company_relations",
        relation.id,
        None,
        row_data(relation),
    )
    _sync_company_text(db, kind, entity_id)
    return relation, "created"


def validate_company_selection(db, kind, payload, before):
    from .catalog_service import fail_fields

    if payload.company_ids is None:
        return
    if kind not in {"groups", "idols"}:
        fail_fields([{"field": "company_ids", "message": "公司归属仅支持组合和艺人"}])
    names = []
    for cid in dict.fromkeys(payload.company_ids):
        company = db.get(CatalogRecord, cid)
        if not company or company.kind != "companies" or company.status == "ARCHIVED":
            fail_fields([{"field": "company_ids", "message": "请选择公司管理中的有效公司"}])
        names.append(company.data["name"])
    if len(" / ".join(names)) > 120:
        fail_fields([{"field": "company_ids", "message": "所选公司名称合计不能超过 120 字符"}])
    current = set(before.get("company_ids", [])) if before else set()
    changed = current != set(payload.company_ids)
    history = records(db, "company_relations", before["id"]) if before else []
    effective = payload.company_effective_date
    if changed and history and not effective:
        fail_fields(
            [
                {
                    "field": "company_effective_date",
                    "message": "公司归属变更需要填写生效日期，保留原公司经历",
                }
            ]
        )
    if effective:
        try:
            day = date.fromisoformat(effective)
            if day > date.today():
                raise ValueError
        except ValueError as exc:
            raise DomainError(
                "INVALID_DATE", "公司生效日期必须为不晚于今天的 YYYY-MM-DD", 422
            ) from exc
        for relation in active_relations(db, kind, before["id"]) if before else []:
            if relation.data["company_id"] not in payload.company_ids:
                if relation.data.get("start_date") and relation.data["start_date"] >= effective:
                    fail_fields(
                        [
                            {
                                "field": "company_effective_date",
                                "message": "变更日期须晚于原经历开始日期；同日纠错请编辑公司经历",
                            }
                        ]
                    )
    if changed and history:
        # Prevent silently replacing a pre-existing scheduled company assignment.
        if any(r.data.get("start_date", "") > date.today().isoformat() for r in history):
            fail_fields(
                [{"field": "company_ids", "message": "存在未来公司经历，请先在公司经历中核对"}]
            )


def sync_company_selection(db, actor, kind, entity_id, payload, before):
    from .catalog_service import audit, row_data

    if payload.company_ids is None or kind not in {"groups", "idols"}:
        return
    selected = set(payload.company_ids)
    current = active_relations(db, kind, entity_id)
    existing = {r.data["company_id"] for r in current}
    for relation in current:
        if relation.data["company_id"] not in selected:
            old = row_data(relation)
            relation.data = {
                **relation.data,
                "end_date": (
                    date.fromisoformat(payload.company_effective_date) - timedelta(days=1)
                ).isoformat(),
            }
            audit(
                db,
                actor,
                "catalog.company_relations.save",
                "company_relations",
                relation.id,
                old,
                row_data(relation),
            )
    for cid in dict.fromkeys(payload.company_ids):
        if cid not in existing:
            relation = CatalogRecord(
                kind="company_relations",
                entity_type=kind,
                entity_id=entity_id,
                data={
                    "company_id": cid,
                    "relation_type": "Agency",
                    "start_date": payload.company_effective_date,
                    "end_date": "",
                    "date_unknown": not bool(payload.company_effective_date),
                    "source": "catalog_company_selection",
                },
            )
            db.add(relation)
            db.flush()
            audit(
                db,
                actor,
                "catalog.company_relations.save",
                "company_relations",
                relation.id,
                None,
                row_data(relation),
            )
