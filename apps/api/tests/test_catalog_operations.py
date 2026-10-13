from datetime import date

from sqlalchemy import select
from test_admin_console import payload

from app.admin_models import ContentMetadata
from app.core.database import SessionLocal
from app.models import Card, Group, GroupMembership, Idol
from app.modules.admin.catalog_companies import company_name_key
from app.modules.admin.catalog_extensions import CatalogRecord

ROOT = "/api/v1/admin/console"


def post(client, headers, path, data):
    response = client.post(ROOT + path, headers=headers, json=data)
    assert response.status_code == 200, response.text
    return response.json()["data"]


def entity(client, headers, kind, **data):
    return post(client, headers, "/entities/" + kind, data)


def record(client, headers, kind, entity_type="", entity_id="", **data):
    return post(
        client,
        headers,
        "/records/" + kind,
        {"entity_type": entity_type, "entity_id": entity_id, "data": data},
    )


def test_solo_album_card_and_collaboration_roundtrip(client, admin_headers):
    idol = entity(client, admin_headers, "idols", name="Independent Solo")
    album = entity(
        client,
        admin_headers,
        "albums",
        name="Solo Release",
        artists=[{"type": "idols", "id": idol["id"]}],
    )
    assert album["artist_name"] == "Independent Solo"
    card = post(
        client,
        admin_headers,
        "/cards",
        payload(group_id=None, idol_id=idol["id"], source_entity_id=album["id"]),
    )
    assert card["group_id"] is None
    for kind, item_id in [("idols", idol["id"]), ("albums", album["id"])]:
        for action in ["submit", "publish"]:
            post(client, admin_headers, f"/entities/{kind}/{item_id}/actions", {"action": action})
    for action in ["submit", "publish"]:
        post(client, admin_headers, f"/cards/{card['id']}/actions", {"action": action})
    album = entity(
        client,
        admin_headers,
        "albums",
        name="Collaboration",
        artists=[{"type": "groups", "id": "group-lumina"}, {"type": "idols", "id": idol["id"]}],
    )
    assert len(album["artists"]) == 2
    assert "Independent Solo" in album["artist_name"]
    public_solo = client.get("/api/v1/catalog/albums/" + card["source_entity_id"]).json()["data"]
    assert public_solo["artists"] == [{"type": "idols", "id": idol["id"]}]


def test_member_history_allows_historical_card_and_preserves_existing_attribution(
    client, admin_headers
):
    with SessionLocal() as db:
        membership = db.scalar(
            select(GroupMembership).where(
                GroupMembership.idol_id == "idol-aria", GroupMembership.group_id == "group-lumina"
            )
        )
        membership.start_date = date(2020, 1, 1)
        membership.end_date = date(2024, 12, 31)
        membership.status = "former"
        db.commit()
    card = post(client, admin_headers, "/cards", payload(release_date="2023-05-01"))
    assert card["group_id"] == "group-lumina"
    for action in ["submit", "publish"]:
        post(client, admin_headers, f"/cards/{card['id']}/actions", {"action": action})
    response = client.post(
        ROOT + "/cards", headers=admin_headers, json=payload(release_date="2025-01-01")
    )
    assert response.status_code == 422
    record(
        client,
        admin_headers,
        "memberships",
        "idols",
        "idol-aria",
        group_id="group-lumina",
        start_date="2025-06-01",
        status="active",
        is_primary=True,
    )
    with SessionLocal() as db:
        assert db.get(Card, card["id"]).group_id == "group-lumina"
        assert (
            db.scalar(
                select(GroupMembership).where(
                    GroupMembership.idol_id == "idol-aria", GroupMembership.status == "former"
                )
            )
            is not None
        )
    post(client, admin_headers, f"/cards/{card['id']}/actions", {"action": "offline"})
    with SessionLocal() as db:
        for membership in db.scalars(
            select(GroupMembership).where(GroupMembership.idol_id == "idol-aria")
        ).all():
            db.delete(membership)
        db.commit()
    saved = client.put(
        ROOT + f"/cards/{card['id']}",
        headers=admin_headers,
        json={**card, "title": "Keep legacy history"},
    )
    assert saved.status_code == 200, saved.text
    assert saved.json()["data"]["group_id"] == "group-lumina"
    assert (
        client.post(
            ROOT + "/cards", headers=admin_headers, json=payload(release_date="2023-05-01")
        ).status_code
        == 422
    )


def test_draft_delete_but_published_then_saved_draft_remains_protected(client, admin_headers):
    draft = post(client, admin_headers, "/cards", payload())
    assert client.delete(ROOT + f"/cards/{draft['id']}", headers=admin_headers).status_code == 200
    card = post(client, admin_headers, "/cards", payload())
    for action in ["submit", "publish", "offline"]:
        post(client, admin_headers, f"/cards/{card['id']}/actions", {"action": action})
    saved = client.put(
        ROOT + f"/cards/{card['id']}", headers=admin_headers, json=payload(title="Updated")
    )
    assert saved.status_code == 200
    assert saved.json()["data"]["ever_published"] is True
    assert client.delete(ROOT + f"/cards/{card['id']}", headers=admin_headers).status_code == 409


def test_source_cycles_and_version_reference_validation(client, admin_headers):
    a = entity(client, admin_headers, "others", name="A", group_id="group-lumina")
    b = entity(client, admin_headers, "others", name="B", group_id="group-lumina")
    record(client, admin_headers, "sources", "others", a["id"], type="others", id=b["id"])
    response = client.post(
        ROOT + "/records/sources",
        headers=admin_headers,
        json={
            "entity_type": "others",
            "entity_id": b["id"],
            "data": {"type": "others", "id": a["id"]},
        },
    )
    assert response.status_code == 422
    version = record(
        client, admin_headers, "versions", "albums", "album-starlit", name="OFF", code="OFF"
    )
    post(client, admin_headers, "/cards", payload(entity_version_id=version["id"]))
    response = client.post(
        ROOT + "/cards",
        headers=admin_headers,
        json=payload(
            source_entity_type="OTHER",
            source_entity_id=a["id"],
            entity_version_id=version["id"],
        ),
    )
    assert response.status_code == 422
    assert (
        client.delete(
            ROOT + f"/records/versions/{version['id']}", headers=admin_headers
        ).status_code
        == 409
    )


def test_bulk_edit_preview_conflict_and_atomic_state_validation(client, admin_headers):
    a = post(client, admin_headers, "/cards", payload(title="A"))
    b = post(client, admin_headers, "/cards", payload(title="B"))
    plan = post(
        client,
        admin_headers,
        "/cards/bulk-edit",
        {"ids": [a["id"], b["id"]], "changes": {"version": "OFF", "add_tags": ["new"]}},
    )
    with SessionLocal() as db:
        assert db.get(Card, a["id"]).version != "OFF"
    post(
        client,
        admin_headers,
        "/cards/bulk-edit",
        {
            "ids": [a["id"], b["id"]],
            "changes": {"version": "OFF", "add_tags": ["new"]},
            "preview": False,
            "expected": {r["id"]: r["updated_at"] for r in plan["items"]},
        },
    )
    response = client.post(
        ROOT + "/cards/bulk-edit",
        headers=admin_headers,
        json={
            "ids": [a["id"]],
            "changes": {"version": "OLD"},
            "preview": False,
            "expected": {a["id"]: a["updated_at"]},
        },
    )
    assert response.status_code == 409
    with SessionLocal() as db:
        assert db.get(Card, b["id"]).version == "OFF"


def test_batch_generation_idempotency_and_validation(client, admin_headers):
    batch = record(
        client,
        admin_headers,
        "batches",
        name="Set",
        group_id="group-lumina",
        source_entity_type="ALBUM",
        source_entity_id="album-starlit",
        version="OFF",
    )
    cards = post(
        client,
        admin_headers,
        f"/batches/{batch['id']}/generate",
        {"member_ids": ["idol-aria"], "cards_per_member": 2},
    )
    assert len(cards["ids"]) == 2
    response = client.post(
        ROOT + f"/batches/{batch['id']}/generate",
        headers=admin_headers,
        json={"member_ids": ["idol-aria"]},
    )
    assert response.status_code == 409
    result = post(client, admin_headers, f"/batches/{batch['id']}/validate", {})
    assert len(result["items"]) == 2
    assert all(r["errors"] for r in result["items"])
    assert (
        client.delete(ROOT + f"/cards/{cards['ids'][0]}", headers=admin_headers).status_code == 409
    )
    for item_id in cards["ids"]:
        post(client, admin_headers, f"/batches/{batch['id']}/remove-card", {"card_id": item_id})
        assert client.delete(ROOT + f"/cards/{item_id}", headers=admin_headers).status_code == 200
    assert (
        client.post(
            ROOT + f"/batches/{batch['id']}/generate",
            headers=admin_headers,
            json={"member_ids": ["idol-aria"]},
        ).status_code
        == 409
    )


def test_feedback_review_changes_official_data_only_after_acceptance(
    client, admin_headers, auth_headers
):
    card = post(client, admin_headers, "/cards", payload())
    for action in ["submit", "publish"]:
        post(client, admin_headers, f"/cards/{card['id']}/actions", {"action": action})
    response = client.post(
        "/api/v1/catalog/feedback",
        headers=auth_headers,
        json={
            "entity_type": "cards",
            "entity_id": card["id"],
            "reason": "Wrong title",
            "suggested": {"title": "Corrected"},
        },
    )
    assert response.status_code == 200, response.text
    item = response.json()["data"]
    assert (
        client.post(
            ROOT + f"/review-queue/contribution/{item['id']}/actions",
            headers=auth_headers,
            json={"action": "accept"},
        ).status_code
        == 403
    )
    post(
        client,
        admin_headers,
        f"/review-queue/contribution/{item['id']}/actions",
        {"action": "accept"},
    )
    with SessionLocal() as db:
        assert db.get(Card, card["id"]).title == "Corrected"
    assert (
        client.post(
            ROOT + f"/review-queue/contribution/{item['id']}/actions",
            headers=admin_headers,
            json={"action": "accept"},
        ).status_code
        == 409
    )


def test_detail_quality_and_index_routes(client, admin_headers):
    for url in ["/entities/groups/group-lumina/detail", "/quality", "/review-queue", "/scan-index"]:
        response = client.get(ROOT + url, headers=admin_headers)
        assert response.status_code == 200, response.text
    card = post(client, admin_headers, "/cards", payload())
    post(client, admin_headers, f"/scan-index/{card['id']}/retry", {})


def test_combined_import_preview_edits_skip_and_confirm(client, admin_headers):
    raw = (
        b"group_code,group_name,idol_name,stage_name,birthday\n"
        b"NEW,New Group,Real A,Stage A,2000-01-01\n"
        b"NEW,New Group,Real B,Stage B,bad\n"
    )
    response = client.post(
        ROOT + "/imports",
        headers=admin_headers,
        data={"kind": "groups_idols"},
        files={"file": ("combined.csv", raw, "text/csv")},
    )
    assert response.status_code == 200, response.text
    task = response.json()["data"]
    assert len(task["rows"]) == 1 and len(task["errors"]) == 1
    task = post(
        client,
        admin_headers,
        f"/imports/{task['id']}/edit-preview",
        {"edits": [{"row": 3, "data": {"birthday": "2001-01-01"}}]},
    )
    assert not task["errors"] and len(task["rows"]) == 2
    result = post(client, admin_headers, f"/imports/{task['id']}/confirm", {})
    assert result["imported_count"] == 2
    assert len({r["group_id"] for r in result["rows"]}) == 1
    with SessionLocal() as db:
        memberships = db.scalars(
            select(GroupMembership).where(GroupMembership.group_id == result["rows"][0]["group_id"])
        ).all()
        assert {membership.idol_id for membership in memberships} == {
            row["idol_id"] for row in result["rows"]
        }
        assert all(row["membership_id"] for row in result["rows"])
    again = post(client, admin_headers, f"/imports/{task['id']}/confirm", {})
    assert again["imported_count"] == 2
    assert (
        client.post(
            ROOT + f"/imports/{task['id']}/edit-preview", headers=admin_headers, json={}
        ).status_code
        == 409
    )


def test_combined_import_updates_entities_by_ids_and_links_missing_membership(
    client, admin_headers
):
    from test_catalog_bulk import confirm, preview

    group = entity(
        client,
        admin_headers,
        "groups",
        name="Linked on import",
        company="Original Group Agency",
    )
    idol = entity(
        client,
        admin_headers,
        "idols",
        name="Existing Unassigned",
        company="Original Idol Agency",
    )
    task = preview(
        client,
        admin_headers,
        "groups_idols",
        [
            {
                "group_id": group["id"],
                "group_code": "LINKED",
                "group_name": group["name"],
                "group_description": "Updated group profile",
                "idol_id": idol["id"],
                "idol_name": idol["name"],
                "idol_description": "Updated idol profile",
                "idol_region": "KR",
            }
        ],
    )
    assert task["errors"] == []
    assert task["rows"][0]["data"]["group_operation"] == "update"
    assert task["rows"][0]["data"]["idol_operation"] == "update"

    response = confirm(client, admin_headers, task)
    assert response.status_code == 200, response.text
    row = response.json()["data"]["rows"][0]
    assert row["created_id"] == idol["id"]
    assert row["import_mode"] == "updated_group_and_idol"
    assert row["membership_operation"] == "created"
    with SessionLocal() as db:
        assert len(db.scalars(select(Idol).where(Idol.name == idol["name"])).all()) == 1
        saved_group = db.get(Group, group["id"])
        saved_idol = db.get(Idol, idol["id"])
        assert saved_group.description == "Updated group profile"
        assert saved_group.company == "Original Group Agency"
        assert saved_idol.bio == "Updated idol profile"
        assert saved_idol.region == "KR"
        assert saved_idol.company == "Original Idol Agency"
        membership = db.scalar(
            select(GroupMembership).where(
                GroupMembership.group_id == group["id"],
                GroupMembership.idol_id == idol["id"],
            )
        )
        assert membership and membership.id == row["membership_id"]


def test_combined_import_supports_existing_group_with_new_idol(client, admin_headers):
    from test_catalog_bulk import confirm, preview

    group = entity(client, admin_headers, "groups", name="Existing Group New Member")
    task = preview(
        client,
        admin_headers,
        "groups_idols",
        [
            {
                "group_id": group["id"],
                "group_code": "EXISTING-GROUP",
                "group_name": group["name"],
                "idol_name": "Brand New Member",
                "idol_region": "CN",
            },
            {
                "group_id": "",
                "group_code": "EXISTING-GROUP",
                "group_name": group["name"],
                "idol_name": "Second Brand New Member",
                "idol_region": "JP",
            },
        ],
    )
    assert task["errors"] == []
    assert all(row["data"]["group_id"] == group["id"] for row in task["rows"])
    response = confirm(client, admin_headers, task)
    assert response.status_code == 200, response.text
    rows = response.json()["data"]["rows"]
    assert all(row["import_mode"] == "updated_group_created_idol" for row in rows)
    with SessionLocal() as db:
        idols = [db.get(Idol, row["idol_id"]) for row in rows]
        assert [(idol.name, idol.region) for idol in idols] == [
            ("Brand New Member", "CN"),
            ("Second Brand New Member", "JP"),
        ]
        assert all(
            db.scalar(
                select(GroupMembership.id).where(
                    GroupMembership.group_id == group["id"],
                    GroupMembership.idol_id == idol.id,
                )
            )
            for idol in idols
        )


def test_combined_import_requires_ids_when_names_already_exist(client, admin_headers):
    from test_catalog_bulk import confirm, preview

    group = entity(client, admin_headers, "groups", name="Needs Explicit Import IDs")
    idol = entity(
        client,
        admin_headers,
        "idols",
        name="Existing Explicit Member",
        group_id=group["id"],
    )
    task = preview(
        client,
        admin_headers,
        "groups_idols",
        [
            {
                "group_code": "NEEDS-ID",
                "group_name": group["name"],
                "idol_name": idol["name"],
            }
        ],
    )
    assert task["rows"] == []
    assert any(error["field"] == "group_id" for error in task["errors"])

    update_task = preview(
        client,
        admin_headers,
        "groups_idols",
        [
            {
                "group_id": group["id"],
                "group_code": "NEEDS-ID",
                "group_name": group["name"],
                "idol_id": idol["id"],
                "idol_name": idol["name"],
                "idol_description": "Updated through explicit IDs",
            }
        ],
    )
    response = confirm(client, admin_headers, update_task)
    assert response.status_code == 200, response.text
    row = response.json()["data"]["rows"][0]
    assert row["membership_operation"] == "existing"
    with SessionLocal() as db:
        assert db.get(Idol, idol["id"]).bio == "Updated through explicit IDs"
        memberships = db.scalars(
            select(GroupMembership).where(
                GroupMembership.group_id == group["id"],
                GroupMembership.idol_id == idol["id"],
            )
        ).all()
        assert len(memberships) == 1


def test_combined_import_persists_group_and_idol_profiles_and_aggregates_group_fields(
    client, admin_headers
):
    from test_catalog_bulk import confirm, preview

    fields = [
        "group_code",
        "group_name",
        "group_name_en",
        "group_company",
        "group_description",
        "group_debut_date",
        "group_region",
        "group_image_url",
        "group_tags",
        "group_source_type",
        "group_source_url",
        "group_copyright_status",
        "idol_name",
        "stage_name",
        "idol_name_en",
        "idol_company",
        "idol_description",
        "birthday",
        "idol_region",
        "idol_gender",
        "idol_image_url",
        "idol_tags",
        "idol_source_type",
        "idol_source_url",
        "idol_copyright_status",
    ]
    first = dict.fromkeys(fields, "")
    first.update(
        {
            "group_code": "PROFILE",
            "group_name": "Profile Group",
            "idol_name": "Profile Real Name",
            "stage_name": "Profile Stage",
            "idol_name_en": "Profile Stage EN",
            "idol_company": "Idol Agency",
            "idol_description": "Artist biography",
            "birthday": "2000-03-04",
            "idol_region": "KR",
            "idol_gender": "F",
            "idol_image_url": "https://example.com/idol.webp",
            "idol_tags": "主唱|队长",
            "idol_source_type": "OFFICIAL",
            "idol_source_url": "https://example.com/idol",
            "idol_copyright_status": "OFFICIAL_SOURCE",
        }
    )
    second = dict.fromkeys(fields, "")
    second.update(
        {
            "group_code": "PROFILE",
            "group_name": "Profile Group",
            "group_name_en": "Profile Group EN",
            "group_company": "Group Agency",
            "group_description": "Group biography",
            "group_debut_date": "2024-01-02",
            "group_region": "KR",
            "group_image_url": "https://example.com/group.webp",
            "group_tags": "新人|女子组合",
            "group_source_type": "OFFICIAL",
            "group_source_url": "https://example.com/group",
            "group_copyright_status": "OFFICIAL_SOURCE",
            "idol_name": "Second Member",
        }
    )
    task = preview(client, admin_headers, "groups_idols", [first, second])
    assert task["errors"] == []
    assert task["rows"][0]["data"]["group_data"]["description"] == "Group biography"

    response = confirm(client, admin_headers, task)
    assert response.status_code == 200, response.text
    with SessionLocal() as db:
        group = db.scalar(select(Group).where(Group.name == "Profile Group"))
        assert group.name_en == "Profile Group EN"
        assert group.company == "Group Agency"
        assert group.description == "Group biography"
        assert group.debut_date == "2024-01-02"
        assert group.region == "KR"
        group_meta = db.scalar(
            select(ContentMetadata).where(
                ContentMetadata.entity_type == "groups",
                ContentMetadata.entity_id == group.id,
            )
        )
        assert group_meta.data["image_url"] == "https://example.com/group.webp"
        assert group_meta.data["tags"] == ["新人", "女子组合"]
        assert group_meta.data["source_info"]["source_type"] == "OFFICIAL"

        idol = db.scalar(select(Idol).where(Idol.name == "Profile Stage"))
        assert idol.name_en == "Profile Stage EN"
        assert idol.company == "Idol Agency"
        assert idol.bio == "Artist biography"
        assert idol.birth_date == "2000-03-04"
        assert idol.region == "KR"
        idol_meta = db.scalar(
            select(ContentMetadata).where(
                ContentMetadata.entity_type == "idols",
                ContentMetadata.entity_id == idol.id,
            )
        )
        assert idol_meta.data["real_name"] == "Profile Real Name"
        assert idol_meta.data["gender"] == "F"
        assert idol_meta.data["image_url"] == "https://example.com/idol.webp"
        assert idol_meta.data["tags"] == ["主唱", "队长"]
        assert idol_meta.data["source_info"]["source_url"] == "https://example.com/idol"
        membership = db.scalar(
            select(GroupMembership).where(
                GroupMembership.group_id == group.id,
                GroupMembership.idol_id == idol.id,
            )
        )
        assert membership


def test_combined_import_reuses_company_inherits_to_idol_and_exposes_company_detail(
    client, admin_headers
):
    from test_catalog_bulk import confirm, preview

    company = record(client, admin_headers, "companies", name="Nova Works")
    task = preview(
        client,
        admin_headers,
        "groups_idols",
        [
            {
                "group_code": "COMPANY-REUSE",
                "group_name": "Company Reuse Group",
                "group_company": "ｎｏｖａ　ｗｏｒｋｓ",
                "idol_name": "Company Reuse Member",
                "idol_company": "",
            }
        ],
    )
    assert task["errors"] == []
    preview_row = task["rows"][0]["data"]
    assert preview_row["group_company_id"] == company["id"]
    assert preview_row["group_company_mode"] == "reuse"
    assert preview_row["idol_company_id"] == company["id"]
    assert preview_row["idol_company_mode"] == "reuse"
    assert preview_row["idol_company_inherited"] is True

    response = confirm(client, admin_headers, task)
    assert response.status_code == 200, response.text
    imported = response.json()["data"]["rows"][0]
    assert imported["group_company_id"] == company["id"]
    assert imported["idol_company_id"] == company["id"]
    assert imported["group_company_relation_operation"] == "created"
    assert imported["idol_company_relation_operation"] == "created"

    update = preview(
        client,
        admin_headers,
        "groups_idols",
        [
            {
                "group_id": imported["group_id"],
                "group_code": "COMPANY-REUSE",
                "group_name": "Company Reuse Group",
                "group_company": "NOVA WORKS",
                "idol_id": imported["idol_id"],
                "idol_name": "Company Reuse Member",
                "idol_company": "",
            }
        ],
    )
    updated = confirm(client, admin_headers, update)
    assert updated.status_code == 200, updated.text
    updated_row = updated.json()["data"]["rows"][0]
    assert updated_row["group_company_relation_operation"] == "existing"
    assert updated_row["idol_company_relation_operation"] == "existing"

    detail = client.get(ROOT + f"/records/companies/{company['id']}/detail", headers=admin_headers)
    assert detail.status_code == 200, detail.text
    detail_data = detail.json()["data"]
    assert detail_data["company"]["group_count"] == 1
    assert detail_data["company"]["idol_count"] == 1
    assert detail_data["groups"][0]["entity_id"] == imported["group_id"]
    assert detail_data["groups"][0]["relation_status"] == "current"
    assert detail_data["idols"][0]["entity_id"] == imported["idol_id"]
    assert detail_data["idols"][0]["groups"][0]["id"] == imported["group_id"]
    with SessionLocal() as db:
        companies = [
            item
            for item in db.scalars(
                select(CatalogRecord).where(CatalogRecord.kind == "companies")
            ).all()
            if company_name_key(item.data["name"]) == company_name_key("Nova Works")
        ]
        relations = db.scalars(
            select(CatalogRecord).where(
                CatalogRecord.kind == "company_relations",
                CatalogRecord.entity_id.in_([imported["group_id"], imported["idol_id"]]),
            )
        ).all()
        assert len(companies) == 1
        assert len(relations) == 2
        assert {relation.data["company_id"] for relation in relations} == {company["id"]}
        assert db.get(Group, imported["group_id"]).company == "Nova Works"
        assert db.get(Idol, imported["idol_id"]).company == "Nova Works"


def test_combined_import_creates_missing_companies_once_and_links_each_entity(
    client, admin_headers
):
    from test_catalog_bulk import confirm, preview

    rows = [
        {
            "group_code": "COMPANY-CREATE",
            "group_name": "Company Create Group",
            "group_company": "Generated Group Agency",
            "idol_name": "Inherited Company Member",
            "idol_company": "",
        },
        {
            "group_code": "COMPANY-CREATE",
            "group_name": "Company Create Group",
            "group_company": "Generated Group Agency",
            "idol_name": "Special Label Member",
            "idol_company": "Generated Special Label",
        },
    ]
    task = preview(client, admin_headers, "groups_idols", rows)
    assert task["errors"] == []
    assert task["rows"][0]["data"]["group_company_mode"] == "create"
    assert task["rows"][0]["data"]["idol_company_inherited"] is True
    assert task["rows"][1]["data"]["idol_company_mode"] == "create"

    response = confirm(client, admin_headers, task)
    assert response.status_code == 200, response.text
    imported = response.json()["data"]["rows"]
    with SessionLocal() as db:
        companies = {
            company.data["name"]: company
            for company in db.scalars(
                select(CatalogRecord).where(CatalogRecord.kind == "companies")
            ).all()
            if company.data["name"] in {"Generated Group Agency", "Generated Special Label"}
        }
        assert set(companies) == {"Generated Group Agency", "Generated Special Label"}
        relations = db.scalars(
            select(CatalogRecord).where(
                CatalogRecord.kind == "company_relations",
                CatalogRecord.entity_id.in_(
                    [imported[0]["group_id"], imported[0]["idol_id"], imported[1]["idol_id"]]
                ),
            )
        ).all()
        linked = {
            (relation.entity_type, relation.entity_id): relation.data["company_id"]
            for relation in relations
        }
        assert linked[("groups", imported[0]["group_id"])] == companies["Generated Group Agency"].id
        assert linked[("idols", imported[0]["idol_id"])] == companies["Generated Group Agency"].id
        assert linked[("idols", imported[1]["idol_id"])] == companies["Generated Special Label"].id


def test_combined_import_rejects_archived_or_ambiguous_company(client, admin_headers):
    from test_catalog_bulk import preview

    archived = record(client, admin_headers, "companies", name="Archived Import Agency")
    with SessionLocal() as db:
        db.get(CatalogRecord, archived["id"]).status = "ARCHIVED"
        db.add_all(
            [
                CatalogRecord(kind="companies", data={"name": "Ambiguous Import Agency"}),
                CatalogRecord(kind="companies", data={"name": "ambiguous import agency"}),
            ]
        )
        db.commit()
    for suffix, company_name, expected in [
        ("ARCHIVED", "Archived Import Agency", "已归档"),
        ("AMBIGUOUS", "Ambiguous Import Agency", "多个同名公司"),
    ]:
        task = preview(
            client,
            admin_headers,
            "groups_idols",
            [
                {
                    "group_code": f"COMPANY-{suffix}",
                    "group_name": f"Company {suffix} Group",
                    "group_company": company_name,
                    "idol_name": f"Company {suffix} Member",
                }
            ],
        )
        assert task["rows"] == []
        assert any(
            error["field"] == "group_company" and expected in error["message"]
            for error in task["errors"]
        )


def test_combined_import_rolls_back_auto_company_when_relation_fails(client, admin_headers):
    from test_catalog_bulk import confirm, preview

    long_company = record(client, admin_headers, "companies", name="L" * 115)
    group = entity(
        client,
        admin_headers,
        "groups",
        name="Company Rollback Group",
        company_ids=[long_company["id"]],
    )
    task = preview(
        client,
        admin_headers,
        "groups_idols",
        [
            {
                "group_id": group["id"],
                "group_code": "COMPANY-ROLLBACK",
                "group_name": group["name"],
                "group_company": "Rollback Agency",
                "group_description": "must roll back",
                "idol_name": "Rollback Member",
            }
        ],
    )
    assert task["errors"] == []
    response = confirm(client, admin_headers, task)
    assert response.status_code == 422, response.text
    with SessionLocal() as db:
        assert db.get(Group, group["id"]).description != "must roll back"
        assert db.scalar(select(Idol).where(Idol.name == "Rollback Member")) is None
        assert not any(
            company_name_key(company.data["name"]) == company_name_key("Rollback Agency")
            for company in db.scalars(
                select(CatalogRecord).where(CatalogRecord.kind == "companies")
            ).all()
        )


def test_combined_import_rejects_conflicting_group_profile_values(client, admin_headers):
    from test_catalog_bulk import preview

    task = preview(
        client,
        admin_headers,
        "groups_idols",
        [
            {
                "group_code": "CONFLICT",
                "group_name": "Conflict Group",
                "group_company": "Agency A",
                "idol_name": "Member A",
            },
            {
                "group_code": "CONFLICT",
                "group_name": "Conflict Group",
                "group_company": "Agency B",
                "idol_name": "Member B",
            },
        ],
    )
    assert len(task["rows"]) == 1
    assert any(error["field"] == "group_company" for error in task["errors"])


def test_detach_does_not_destroy_owned_and_allows_unreferenced_offline_delete(
    client, admin_headers
):
    from app.models import UserCollectionItem

    a = post(client, admin_headers, "/cards", payload())
    for action in ["submit", "publish", "offline"]:
        post(client, admin_headers, f"/cards/{a['id']}/actions", {"action": action})
    with SessionLocal() as db:
        db.add(UserCollectionItem(user_id="user-demo", card_id=a["id"], quantity=2))
        db.commit()
    assert (
        client.post(ROOT + f"/detach/cards/{a['id']}", headers=admin_headers, json={}).status_code
        == 409
    )
    with SessionLocal() as db:
        owned = db.scalar(select(UserCollectionItem).where(UserCollectionItem.card_id == a["id"]))
        assert owned.quantity == 2
        db.delete(owned)
        db.commit()
    post(client, admin_headers, f"/detach/cards/{a['id']}", {})
    assert client.delete(ROOT + f"/cards/{a['id']}", headers=admin_headers).status_code == 200


def test_manual_merge_preserves_owned_wishlist_and_binder(client, admin_headers):
    from app.models import AlbumCard, CardAlbum, UserCollectionItem, UserWishlistItem

    source = post(client, admin_headers, "/cards", payload(title="Duplicate"))
    target = post(client, admin_headers, "/cards", payload(title="Canonical"))
    for action in ["submit", "publish"]:
        post(client, admin_headers, f"/cards/{target['id']}/actions", {"action": action})
    with SessionLocal() as db:
        db.add_all(
            [
                UserCollectionItem(user_id="user-demo", card_id=source["id"], quantity=2),
                UserCollectionItem(user_id="user-demo", card_id=target["id"], quantity=3),
                UserWishlistItem(user_id="user-demo", card_id=source["id"]),
            ]
        )
        album = db.scalar(select(CardAlbum))
        db.add(AlbumCard(album_id=album.id, card_id=source["id"], sort_order=1))
        db.commit()
    plan = post(
        client,
        admin_headers,
        "/cards/merge",
        {"source_id": source["id"], "target_id": target["id"]},
    )
    post(
        client,
        admin_headers,
        "/cards/merge",
        {
            "source_id": source["id"],
            "target_id": target["id"],
            "preview": False,
            "expected": plan["expected"],
        },
    )
    with SessionLocal() as db:
        assert (
            db.scalar(
                select(UserCollectionItem).where(UserCollectionItem.card_id == target["id"])
            ).quantity
            == 5
        )
        assert (
            db.scalar(select(UserWishlistItem).where(UserWishlistItem.card_id == target["id"]))
            is not None
        )
        assert db.scalar(select(AlbumCard).where(AlbumCard.card_id == target["id"])) is not None
        assert db.get(Card, source["id"]).status == "ARCHIVED"
    assert client.get("/api/v1/catalog/cards/" + source["id"]).json()["data"]["id"] == target["id"]


def test_membership_legacy_edit_and_company_history(client, admin_headers):
    existing = client.get(
        ROOT + "/records/memberships?entity_id=idol-aria", headers=admin_headers
    ).json()["data"]["items"][0]
    assert existing["id"].startswith("legacy-")
    record(
        client,
        admin_headers,
        "memberships",
        "idols",
        "idol-aria",
        **{**existing["data"], "status": "inactive", "is_primary": True},
    )
    company = record(client, admin_headers, "companies", name="New Agency")
    record(
        client,
        admin_headers,
        "company_relations",
        "idols",
        "idol-aria",
        company_id=company["id"],
        start_date="2025-01-01",
    )
    data = client.get(ROOT + "/entities/idols/idol-aria/detail", headers=admin_headers).json()[
        "data"
    ]
    assert data["entity"]["company"] == "New Agency"
    post(client, admin_headers, "/entities/idols/idol-aria/actions", {"action": "offline"})
    current = data["entity"]
    updated = client.put(
        ROOT + "/entities/idols/idol-aria",
        headers=admin_headers,
        json={
            **current,
            "description": "Biography update",
            "release_date": current["birth_date"],
        },
    )
    assert updated.status_code == 200, updated.text
    with SessionLocal() as db:
        member = db.get(GroupMembership, existing["data"]["membership_id"])
        assert member.status == "inactive"
        assert member.end_date is None
    for action in ["submit", "publish"]:
        post(client, admin_headers, "/entities/idols/idol-aria/actions", {"action": action})
    public = client.get("/api/v1/catalog/bootstrap").json()["data"]
    group = next(g for g in public["groups"] if g["id"] == "group-lumina")
    assert "idol-aria" in group["member_ids"]
    assert "idol-aria" not in group["former_member_ids"]
    idol = next(i for i in public["idols"] if i["id"] == "idol-aria")
    assert idol["company"] == "New Agency"
    assert (
        client.delete(
            ROOT + f"/records/companies/{company['id']}", headers=admin_headers
        ).status_code
        == 409
    )


def test_solo_import_distinguishes_artists_and_rechecks_duplicates(client, admin_headers):
    from test_catalog_bulk import confirm, preview

    first = entity(client, admin_headers, "idols", name="Solo import one")
    second = entity(client, admin_headers, "idols", name="Solo import two")
    task = preview(
        client,
        admin_headers,
        "albums",
        [
            {"name": "Same title", "idol_id": first["id"]},
            {"name": "Same title", "idol_id": second["id"]},
        ],
    )
    assert len(task["rows"]) == 2, task
    assert confirm(client, admin_headers, task).status_code == 200
    duplicate = preview(
        client, admin_headers, "albums", [{"name": "Same title", "idol_id": first["id"]}]
    )
    assert not duplicate["rows"]
    assert duplicate["errors"][0]["field"] == "name"


def test_missing_content_feedback_publishes_in_same_review(client, auth_headers, admin_headers):
    response = client.post(
        "/api/v1/catalog/feedback",
        headers=auth_headers,
        json={
            "entity_type": "albums",
            "reason": "缺少个人发行",
            "suggested": {
                "name": "Suggested solo album",
                "artists": [{"type": "idols", "id": "idol-aria"}],
            },
        },
    )
    assert response.status_code == 200, response.text
    item_id = response.json()["data"]["id"]
    post(
        client, admin_headers, f"/review-queue/contribution/{item_id}/actions", {"action": "accept"}
    )
    queue = client.get(ROOT + "/review-queue", headers=admin_headers).json()["data"]["items"]
    row = next(r for r in queue if r["id"] == item_id)
    assert row["entity_id"]
    detail = client.get(
        ROOT + f"/entities/albums/{row['entity_id']}/detail", headers=admin_headers
    ).json()["data"]
    assert detail["entity"]["status"] == "PUBLISHED"
    assert client.get("/api/v1/catalog/albums/" + row["entity_id"]).status_code == 200
    assert (
        client.post(
            ROOT + f"/review-queue/contribution/{item_id}/actions",
            headers=admin_headers,
            json={"action": "accept"},
        ).status_code
        == 409
    )
