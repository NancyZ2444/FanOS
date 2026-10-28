"""Company spreadsheet preflight and transactional creation using the company registry."""

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from .catalog_companies import company_name_key
from .catalog_extensions import CatalogRecord, records
from .catalog_service import audit, fail_fields, row_data

COLUMNS = ["name", "description"]


class CompanyDraft(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    name: str = Field(min_length=1, max_length=120)
    description: str = Field(default="", max_length=2000)


def duplicate_errors(db, name):
    if any(
        company_name_key(r.data["name"]) == company_name_key(name) for r in records(db, "companies")
    ):
        return [{"field": "name", "message": "公司已存在（含归档记录），请编辑已有公司"}]
    return []


def validate_rows(db, rows):
    valid, errors, seen = [], [], set()
    for number, raw in enumerate(rows, 2):
        try:
            draft = CompanyDraft.model_validate({k: str(v or "").strip() for k, v in raw.items()})
            draft.name = " ".join(draft.name.split())
            problems = duplicate_errors(db, draft.name)
            key = company_name_key(draft.name)
            if key in seen:
                problems.append({"field": "name", "message": "文件内公司名称重复"})
            if not problems:
                seen.add(key)
                valid.append({"row": number, "data": draft.model_dump()})
        except (ValidationError, TypeError):
            problems = [
                {
                    "field": "name",
                    "message": "请填写 1–120 字符公司名称，描述不超过 2000 字符，并检查列数",
                }
            ]
        errors.extend(
            {"row": number, **p, "suggestion": p["message"], "can_skip": True} for p in problems
        )
    return valid, errors


def create_company(db, actor, row):
    draft = CompanyDraft.model_validate(row["data"])
    fail_fields([{**e, "row": row["row"]} for e in duplicate_errors(db, draft.name)])
    company = CatalogRecord(kind="companies", data={**draft.model_dump(), "enabled": True})
    db.add(company)
    db.flush()
    audit(db, actor, "catalog.companies.save", "companies", company.id, None, row_data(company))
    return company.id
