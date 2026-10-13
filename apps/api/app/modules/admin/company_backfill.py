"""Idempotent backfill from existing group company text; never guesses dates."""

from types import SimpleNamespace

from sqlalchemy import select

from app.models import Group

from .catalog_companies import company_name_key
from .catalog_extensions import CatalogRecord, records
from .catalog_service import audit, meta_for, row_data


def backfill_group_companies(db, *, apply=False):
    companies = records(db, "companies")
    by_name = {}
    for company in companies:
        by_name.setdefault(company_name_key(company.data.get("name", "")), []).append(company)
    report = {"applied": apply, "companies_created": [], "relations_created": [], "skipped": []}
    actor = SimpleNamespace(id="system:company-backfill")
    for group in db.scalars(select(Group).order_by(Group.id)).all():
        if records(db, "company_relations", group.id):
            report["skipped"].append({"group_id": group.id, "reason": "existing_company_history"})
            continue
        meta = meta_for(db, "groups", group.id)
        raw = (meta.data.get("company", group.company) if meta else group.company) or ""
        name = " ".join(raw.split())
        key = company_name_key(name)
        if key in {"", "unknown", "暂无", "未知", "待确认", "n/a", "-"}:
            report["skipped"].append({"group_id": group.id, "reason": "company_unspecified"})
            continue
        matches = by_name.get(key, [])
        if len(matches) > 1 or (matches and matches[0].status == "ARCHIVED"):
            report["skipped"].append(
                {"group_id": group.id, "reason": "company_ambiguous_or_archived"}
            )
            continue
        if not matches:
            company = CatalogRecord(
                kind="companies",
                data={
                    "name": name,
                    "source": "legacy_group_company_backfill",
                },
            )
            if apply:
                db.add(company)
                db.flush()
                audit(
                    db,
                    actor,
                    "catalog.company.backfill",
                    "companies",
                    company.id,
                    None,
                    row_data(company),
                )
            else:
                company.id = "planned:" + key
                company.status = "DRAFT"
            by_name[key] = [company]
            report["companies_created"].append({"id": company.id, "name": name})
        else:
            company = matches[0]
        data = {
            "company_id": company.id,
            "relation_type": "Agency",
            "start_date": "",
            "end_date": "",
            "date_unknown": True,
            "source": "legacy_group_company_backfill",
            "original_company": raw,
            "remark": "来自原组合公司字段；归属期间待核实。",
        }
        relation = CatalogRecord(
            kind="company_relations", entity_type="groups", entity_id=group.id, data=data
        )
        if apply:
            db.add(relation)
            db.flush()
            audit(
                db,
                actor,
                "catalog.company.backfill",
                "company_relations",
                relation.id,
                None,
                row_data(relation),
            )
        report["relations_created"].append(
            {
                "group_id": group.id,
                "group_name": group.name,
                "company_id": company.id,
                "company_name": company.data["name"],
            }
        )
    return report
