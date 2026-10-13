from datetime import date

from sqlalchemy import select
from test_catalog_operations import ROOT, entity, record

from app.core.database import SessionLocal
from app.models import Group, GroupMembership, OperationLog
from app.modules.admin.catalog_extensions import CatalogRecord
from app.modules.admin.catalog_service import entity_payload, row_data
from app.modules.admin.company_backfill import backfill_group_companies


def test_idol_payload_exposes_all_history_without_changing_primary_group():
    with SessionLocal() as db:
        db.add(
            GroupMembership(
                idol_id="idol-aria",
                group_id="group-aster",
                status="former",
                start_date=date(2010, 1, 1),
                end_date=date(2012, 1, 1),
            )
        )
        db.flush()
        from app.models import Idol

        data = entity_payload(db, "idols", db.get(Idol, "idol-aria"))
        assert data["group_id"] == "group-lumina"
        assert {m["group_id"] for m in data["membership_history"]} == {
            "group-lumina",
            "group-aster",
        }


def test_company_selection_and_repeated_save_are_idempotent(client, admin_headers):
    company = record(client, admin_headers, "companies", name="New Agency")
    for kind in ["groups", "idols"]:
        data = {"name": "New " + kind, "company_ids": [company["id"]]}
        created = entity(client, admin_headers, kind, **data)
        assert created["company_ids"] == [company["id"]]
        assert created["company"] == "New Agency"
        saved = client.put(
            f"{ROOT}/entities/{kind}/{created['id']}", headers=admin_headers, json=data
        )
        assert saved.status_code == 200, saved.text
        relations = client.get(
            f"{ROOT}/records/company_relations?entity_id={created['id']}", headers=admin_headers
        ).json()["data"]["items"]
        assert len(relations) == 1
        assert relations[0]["data"]["date_unknown"] is True
        assert relations[0]["data"]["start_date"] == ""


def test_company_change_requires_date_and_preserves_original_history(client, admin_headers):
    a = record(client, admin_headers, "companies", name="Agency A")
    b = record(client, admin_headers, "companies", name="Agency B")
    created = entity(
        client,
        admin_headers,
        "groups",
        name="Move agency",
        company_ids=[a["id"]],
        company_effective_date="2020-01-01",
    )
    data = {"name": created["name"], "company_ids": [b["id"]]}
    url = f"{ROOT}/entities/groups/{created['id']}"
    assert client.put(url, headers=admin_headers, json=data).status_code == 422
    data["company_effective_date"] = "2019-01-01"
    assert client.put(url, headers=admin_headers, json=data).status_code == 422
    data["company_effective_date"] = "2024-01-01"
    saved = client.put(url, headers=admin_headers, json=data)
    assert saved.status_code == 200, saved.text
    assert saved.json()["data"]["company_ids"] == [b["id"]]
    with SessionLocal() as db:
        rows = db.scalars(
            select(CatalogRecord).where(CatalogRecord.entity_id == created["id"])
        ).all()
        old = next(r for r in rows if r.data["company_id"] == a["id"])
        assert old.data["start_date"] == "2020-01-01"
        assert old.data["end_date"] == "2023-12-31"
    # Explicitly remove current affiliation, without reviving the legacy display string.
    cleared = client.put(
        url,
        headers=admin_headers,
        json={**data, "company_ids": [], "company_effective_date": "2025-01-01"},
    )
    assert cleared.json()["data"]["company"] == ""


def test_invalid_company_is_rejected_atomically_and_names_are_deduplicated(client, admin_headers):
    record(client, admin_headers, "companies", name="  Agency    ONE ")
    assert (
        client.post(
            ROOT + "/records/companies",
            headers=admin_headers,
            json={"data": {"name": "agency one"}},
        ).status_code
        == 409
    )
    assert (
        client.post(
            ROOT + "/entities/groups",
            headers=admin_headers,
            json={"name": "Invalid company", "company_ids": ["bad-id"]},
        ).status_code
        == 422
    )
    with SessionLocal() as db:
        assert db.scalar(select(Group).where(Group.name == "Invalid company")) is None


def test_legacy_company_is_preserved_when_new_selection_is_omitted(client, admin_headers):
    created = entity(
        client, admin_headers, "groups", name="Legacy company", company="Original text"
    )
    saved = client.put(
        f"{ROOT}/entities/groups/{created['id']}",
        headers=admin_headers,
        json={"name": created["name"]},
    )
    assert saved.json()["data"]["company"] == "Original text"


def test_backfill_reuses_company_and_is_read_only_on_preview_and_idempotent_on_apply():
    with SessionLocal() as db:
        existing = CatalogRecord(kind="companies", data={"name": " NORTH   STAR STUDIO "})
        db.add(existing)
        db.commit()
        before = [row_data(g) for g in db.scalars(select(Group)).all()]
        preview = backfill_group_companies(db)
        assert len(preview["relations_created"]) == len(before)
        assert db.scalars(
            select(CatalogRecord).where(CatalogRecord.kind != "taxonomy_migrations")
        ).all() == [existing]
        applied = backfill_group_companies(db, apply=True)
        db.commit()
        assert len(applied["companies_created"]) == len(before) - 1
        assert (
            next(r for r in applied["relations_created"] if r["group_id"] == "group-lumina")[
                "company_id"
            ]
            == existing.id
        )
        assert [row_data(g) for g in db.scalars(select(Group)).all()] == before
        again = backfill_group_companies(db, apply=True)
        assert not again["relations_created"] and not again["companies_created"]
        assert db.scalar(
            select(OperationLog).where(OperationLog.action == "catalog.company.backfill")
        )


def test_backfill_respects_existing_company_history_and_ambiguous_names():
    with SessionLocal() as db:
        a = CatalogRecord(kind="companies", data={"name": "North Star Studio"})
        b = CatalogRecord(kind="companies", data={"name": "north star studio"})
        db.add_all([a, b])
        db.flush()
        db.add(
            CatalogRecord(
                kind="company_relations",
                entity_type="groups",
                entity_id="group-aster",
                data={"company_id": a.id, "start_date": "2020-01-01", "end_date": "2021-01-01"},
            )
        )
        db.commit()
        report = backfill_group_companies(db, apply=True)
        skipped = {r["group_id"]: r["reason"] for r in report["skipped"]}
        assert skipped["group-lumina"] == "company_ambiguous_or_archived"
        assert skipped["group-aster"] == "existing_company_history"
