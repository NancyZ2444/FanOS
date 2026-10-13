from datetime import date

from sqlalchemy import select
from test_admin_console import payload

from app.core.database import SessionLocal
from app.models import Card, GroupMembership

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
    again = post(client, admin_headers, f"/imports/{task['id']}/confirm", {})
    assert again["imported_count"] == 2
    assert (
        client.post(
            ROOT + f"/imports/{task['id']}/edit-preview", headers=admin_headers, json={}
        ).status_code
        == 409
    )


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
