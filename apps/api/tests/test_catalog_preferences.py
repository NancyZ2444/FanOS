import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.core.database import SessionLocal
from app.models import Card
from app.modules.admin.import_service import columns, validate_rows

ROOT = "/api/v1/admin/console"


def test_events_require_the_correct_location(client, admin_headers):
    base = {"name": "Event", "group_id": "group-lumina"}
    for extra, field in [
        ({}, "city"),
        ({"is_online": True, "city": "Seoul", "platform": "  "}, "platform"),
    ]:
        result = client.post(
            f"{ROOT}/entities/events", headers=admin_headers, json={**base, **extra}
        )
        assert result.status_code == 422
        assert result.json()["data"]["details"][0]["field"] == field
    for extra in [{"city": "Seoul"}, {"is_online": True, "platform": "Weverse"}]:
        result = client.post(
            f"{ROOT}/entities/events", headers=admin_headers, json={**base, **extra}
        )
        assert result.status_code == 200, result.text
        event = result.json()["data"]
        for action in ["submit", "publish"]:
            assert (
                client.post(
                    f"{ROOT}/entities/events/{event['id']}/actions",
                    headers=admin_headers,
                    json={"action": action},
                ).status_code
                == 200
            )
        public = client.get(f"/api/v1/catalog/events/{event['id']}").json()["data"]
        assert public["platform"] == extra.get("platform", "")


def test_event_import_location_and_card_template():
    assert {"city", "is_online", "platform"} <= set(columns("events"))
    assert "title" not in columns("cards") and "card_number" not in columns("cards")
    with SessionLocal() as db:
        _, errors = validate_rows(db, "events", [{"name": "Import", "group_id": "group-lumina"}])
        assert errors
        valid, errors = validate_rows(
            db,
            "events",
            [
                {
                    "name": "Import",
                    "group_id": "group-lumina",
                    "is_online": "true",
                    "platform": "YouTube",
                }
            ],
        )
        assert not errors, errors
        assert len(valid) == 1


def test_card_numbers_are_generated_immutable_and_unique(client, admin_headers):
    payload = {
        "group_id": "group-lumina",
        "idol_id": "idol-aria",
        "source_entity_id": "album-starlit",
        "card_number": "spoofed",
    }
    cards = []
    for _ in range(2):
        result = client.post(f"{ROOT}/cards", headers=admin_headers, json=payload)
        assert result.status_code == 200, result.text
        cards.append(result.json()["data"])
    a, b = cards
    assert a["card_number"].startswith("FOS-")
    assert a["card_number"] != b["card_number"]
    assert a["title"]  # Generated compatibility label, no required user-entered name.
    result = client.put(
        f"{ROOT}/cards/{a['id']}",
        headers=admin_headers,
        json={**payload, "card_number": b["card_number"]},
    )
    assert result.json()["data"]["card_number"] == a["card_number"]
    with SessionLocal() as db:
        db.get(Card, b["id"]).card_number = a["card_number"]
        with pytest.raises(IntegrityError):
            db.flush()
        db.rollback()
        assert len(set(db.scalars(select(Card.card_number)))) == len(
            list(db.scalars(select(Card.id)))
        )
        seeded_number = db.get(Card, "card-aria-01").card_number
    listed = client.get("/api/v1/catalog/cards", params={"q": seeded_number}).json()["data"]
    assert [c["id"] for c in listed["items"]] == ["card-aria-01"]
    searched = client.get("/api/v1/catalog/search", params={"q": seeded_number}).json()["data"]
    assert [c["id"] for c in searched["cards"]] == ["card-aria-01"]


def test_favorite_highlight_can_stay_unset_across_requests(client, auth_headers):
    ids = ["idol-aria", "idol-lin"]
    for primary in [None, "idol-lin", None]:
        assert (
            client.put(
                "/api/v1/me/favorites",
                headers=auth_headers,
                json={"idol_ids": ids, "primary_idol_id": primary},
            ).status_code
            == 200
        )
        profile = client.get("/api/v1/me/profile", headers=auth_headers).json()["data"]
        assert set(profile["favorite_idol_ids"]) == set(ids)
        assert profile["primary_idol_id"] == primary


def test_name_preferences_private_persistent_and_clearable(client, auth_headers, second_app_headers):
    root = "/api/v1/me/name-preferences"
    assert client.get(root).status_code == 401
    assert client.get(root, headers=auth_headers).json()["data"]["mode"] == "official"
    for kind, identifier in [("groups", "group-lumina"), ("idols", "idol-aria")]:
        assert (
            client.put(
                f"{root}/{kind}/{identifier}", headers=auth_headers, json={"remark": "  我的备注  "}
            ).status_code
            == 200
        )
    assert client.patch(root, headers=auth_headers, json={"mode": "combined"}).status_code == 200
    preferences = client.get(root, headers=auth_headers).json()["data"]
    assert preferences["aliases"]["idols"]["idol-aria"] == "我的备注"
    assert preferences["mode"] == "combined"
    assert client.get(root, headers=second_app_headers).json()["data"]["aliases"] == {
        "groups": {},
        "idols": {},
    }
    assert "我的备注" not in client.get("/api/v1/catalog/bootstrap").text
    assert (
        client.put(
            f"{root}/idols/idol-aria", headers=auth_headers, json={"remark": " "}
        ).status_code
        == 200
    )
    assert (
        "idol-aria" not in client.get(root, headers=auth_headers).json()["data"]["aliases"]["idols"]
    )
    assert (
        client.put(f"{root}/groups/missing", headers=auth_headers, json={"remark": "x"}).status_code
        == 404
    )
    assert (
        client.put(
            f"{root}/idols/idol-aria", headers=auth_headers, json={"remark": "a" * 41}
        ).status_code
        == 422
    )
