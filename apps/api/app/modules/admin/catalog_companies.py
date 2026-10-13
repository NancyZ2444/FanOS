"""Company selections create dated relationships without rewriting company history."""

import unicodedata
from datetime import date, timedelta

from app.common.response import DomainError

from .catalog_extensions import CatalogRecord, records


def company_name_key(name: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", name).split()).casefold()


def active_relations(db, kind, entity_id):
    today = date.today().isoformat()
    return [
        r
        for r in records(db, "company_relations", entity_id)
        if r.entity_type == kind
        and (not r.data.get("start_date") or r.data["start_date"] <= today)
        and (not r.data.get("end_date") or r.data["end_date"] >= today)
    ]


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
