from __future__ import annotations

import csv
import io

from sqlalchemy import select

from app.admin_models import CardImageVersion
from app.core.database import SessionLocal
from app.future_models import NotificationInboxItem, OutboxEvent
from app.models import Card, OperationLog

ROOT = "/api/v1/admin/console"


def payload(**extra):
    return {
        "title": "Admin test card",
        "group_id": "group-lumina",
        "idol_id": "idol-aria",
        "source_entity_type": "ALBUM",
        "source_entity_id": "album-starlit",
        "image_url": "https://assets.example.test/front.webp",
        "front_source": {
            "source_type": "OFFICIAL",
            "source_url": "https://official.example.test/card",
            "copyright_status": "AUTHORIZED",
        },
        **extra,
    }


def create(client, headers, **extra):
    res = client.post(ROOT + "/cards", headers=headers, json=payload(**extra))
    assert res.status_code == 200, res.text
    return res.json()["data"]


def action(client, headers, card_id, act, **extra):
    return client.post(
        f"{ROOT}/cards/{card_id}/actions", headers=headers, json={"action": act, **extra}
    )


def test_catalog_lifecycle_and_public_visibility(client, admin_headers):
    card = create(client, admin_headers)
    assert card["status"] == "DRAFT"
    assert client.get("/api/v1/catalog/cards/" + card["id"]).status_code == 404
    assert action(client, admin_headers, card["id"], "publish").status_code == 409
    assert action(client, admin_headers, card["id"], "submit").status_code == 200
    assert action(client, admin_headers, card["id"], "publish").status_code == 200
    assert client.get("/api/v1/catalog/cards/" + card["id"]).status_code == 200
    assert (
        client.put(
            ROOT + "/cards/" + card["id"], headers=admin_headers, json=payload(title="unreviewed")
        ).status_code
        == 409
    )
    assert action(client, admin_headers, card["id"], "offline").status_code == 200
    assert client.get("/api/v1/catalog/cards/" + card["id"]).status_code == 404
    with SessionLocal() as db:
        assert db.get(Card, card["id"]).status == "OFFLINE"
        assert db.scalar(select(OperationLog).where(OperationLog.action == "catalog.card.publish"))
        assert db.scalar(select(OutboxEvent).where(OutboxEvent.aggregate_id == card["id"]))


def test_personal_group_double_sided_ar_validation(client, admin_headers):
    card = create(client, admin_headers, idol_id=None, is_double_sided=True, has_ar=True)
    res = action(client, admin_headers, card["id"], "submit")
    assert res.status_code == 422
    fields = {e["field"] for e in res.json()["data"]["details"]}
    assert {"idol_id", "back_image_url", "ar_resource"} <= fields
    group_card = create(client, admin_headers, idol_id=None, is_group_pc=True)
    assert action(client, admin_headers, group_card["id"], "submit").status_code == 200
    assert action(client, admin_headers, group_card["id"], "publish").status_code == 200
    public_group = client.get("/api/v1/catalog/cards/" + group_card["id"]).json()["data"]
    assert public_group["idol_id"] == ""  # Flutter's existing model requires a string.
    assert public_group["is_group_pc"] is True
    assert "front_source" not in public_group
    mismatch = client.post(
        ROOT + "/cards", headers=admin_headers, json=payload(idol_id="idol-yuna")
    )
    assert mismatch.status_code == 422
    assert mismatch.json()["data"]["details"][0]["field"] == "idol_id"
    missing = client.post(ROOT + "/cards", headers=admin_headers, json=payload(title=""))
    assert missing.status_code == 200
    assert missing.json()["data"]["card_number"].startswith("FOS-")
    bad_url = client.post(
        ROOT + "/cards", headers=admin_headers, json=payload(image_url="javascript:alert(1)")
    )
    assert bad_url.status_code == 422


def test_source_history_optimistic_lock_and_draft_archive(client, admin_headers):
    card = create(client, admin_headers)
    second = client.put(
        ROOT + "/cards/" + card["id"],
        headers=admin_headers,
        json=payload(image_url="https://assets.example.test/v2.webp"),
    )
    assert second.status_code == 200
    history = client.get(
        ROOT + "/cards/" + card["id"] + "/source-history", headers=admin_headers
    ).json()["data"]["items"]
    assert {r["version"] for r in history} == {1, 2}
    conflict = client.put(
        ROOT + "/cards/" + card["id"],
        headers=admin_headers,
        json=payload(expected_updated_at="2020-01-01T00:00:00"),
    )
    assert conflict.status_code == 409
    assert action(client, admin_headers, card["id"], "archive").status_code == 200
    assert action(client, admin_headers, card["id"], "restore").json()["data"]["status"] == "DRAFT"


def test_backend_permissions_and_legacy_endpoints(
    client, admin_headers, auth_headers, admin_actor_headers
):
    assert client.get(ROOT + "/catalog").status_code == 401
    assert client.get(ROOT + "/catalog", headers=auth_headers).status_code == 401
    content = admin_actor_headers("content_operator", "operator")
    ops = admin_actor_headers("operation_admin", "ops")
    card = create(client, content)
    assert action(client, content, card["id"], "submit").status_code == 200
    assert action(client, content, card["id"], "publish").status_code == 403
    assert action(client, content, card["id"], "reject", reason="需修改").status_code == 403
    assert client.post(ROOT + "/cards", headers=ops, json=payload()).status_code == 403
    assert client.get(ROOT + "/operations/users", headers=content).status_code == 403
    assert (
        client.patch(
            "/api/v1/admin/users/current-user/status", headers=content, json={"is_active": False}
        ).status_code
        == 403
    )
    assert client.get(ROOT + "/logs", headers=content).status_code == 403
    assert client.get(ROOT + "/operations/users", headers=ops).status_code == 200


def test_batch_transition_is_atomic(client, admin_headers):
    first = create(client, admin_headers)
    second = create(client, admin_headers)
    action(client, admin_headers, first["id"], "submit")
    res = client.post(
        ROOT + "/cards/batch",
        headers=admin_headers,
        json={"ids": [first["id"], second["id"]], "action": "publish"},
    )
    assert res.status_code == 409
    with SessionLocal() as db:
        assert db.get(Card, first["id"]).status == "PENDING"


def test_import_row_errors_skip_and_idempotent_confirmation(client, admin_headers):
    content = io.StringIO()
    writer = csv.DictWriter(
        content,
        fieldnames=[
            "title",
            "group_id",
            "idol_id",
            "source_entity_id",
            "image_url",
            "front_source_url",
            "front_copyright_status",
        ],
    )
    writer.writeheader()
    valid = {
        "title": "Imported",
        "group_id": "group-lumina",
        "idol_id": "idol-aria",
        "source_entity_id": "album-starlit",
        "image_url": "https://assets.example.test/front.webp",
        "front_source_url": "https://official.example.test/card",
        "front_copyright_status": "AUTHORIZED",
    }
    writer.writerow(valid)
    writer.writerow({**valid, "idol_id": "missing-idol"})
    task = client.post(
        ROOT + "/imports",
        headers=admin_headers,
        files={"file": ("cards.csv", content.getvalue().encode(), "text/csv")},
    ).json()["data"]
    assert len(task["rows"]) == 1
    assert task["errors"][0]["row"] == 3
    assert task["errors"][0]["field"] == "idol_id"
    assert (
        client.post(
            ROOT + "/imports/" + task["id"] + "/confirm",
            headers=admin_headers,
            json={"skip_invalid": False},
        ).status_code
        == 422
    )
    for _ in range(2):
        res = client.post(
            ROOT + "/imports/" + task["id"] + "/confirm",
            headers=admin_headers,
            json={"skip_invalid": True},
        )
        assert res.json()["data"]["imported_count"] == 1
    with SessionLocal() as db:
        assert len(db.scalars(select(Card).where(Card.title == "Imported")).all()) == 1


def test_upload_decode_size_and_image_index(client, admin_headers):
    from conftest import scan_artwork

    invalid = client.post(
        ROOT + "/uploads",
        headers=admin_headers,
        files={"file": ("fake.png", b"not an image", "image/png")},
    )
    assert invalid.status_code == 422
    buffer = io.BytesIO()
    scan_artwork(123).save(buffer, format="PNG")
    uploaded = client.post(
        ROOT + "/uploads",
        headers=admin_headers,
        files={"file": ("card.png", buffer.getvalue(), "image/png")},
    ).json()["data"]
    assert set(uploaded["variants"]) == {"original", "medium", "thumbnail"}
    card = create(client, admin_headers, image_url=uploaded["url"])
    from app.modules.admin.catalog_jobs import process_pending, storage_bytes

    assert process_pending() == 1
    with SessionLocal() as db:
        event = db.scalar(select(OutboxEvent).where(OutboxEvent.aggregate_id == card["id"]))
        assert event.published_at
        assert (
            len(
                db.scalars(
                    select(CardImageVersion).where(CardImageVersion.card_id == card["id"])
                ).all()
            )
            == 1
        )
    import pytest

    with pytest.raises(ValueError):
        storage_bytes("http://169.254.169.254/latest/meta-data/")


def test_entities_stay_private_until_reviewed(client, admin_headers):
    row = client.post(
        ROOT + "/entities/groups",
        headers=admin_headers,
        json={"name": "New Group", "name_en": "New Group"},
    ).json()["data"]
    assert client.get("/api/v1/catalog/groups/" + row["id"]).status_code == 404
    for act in ("submit", "publish"):
        assert (
            client.post(
                ROOT + "/entities/groups/" + row["id"] + "/actions",
                headers=admin_headers,
                json={"action": act},
            ).status_code
            == 200
        )
    assert client.get("/api/v1/catalog/groups/" + row["id"]).status_code == 200


def test_notification_review_test_delivery_and_target_validation(
    client, admin_headers, auth_headers
):
    row = client.post(
        ROOT + "/operations/notifications",
        headers=admin_headers,
        json={
            "title": "Catalog update",
            "content": "Hello fans",
            "audience": "ALL",
            "target_type": "CARD",
            "target_id": "card-aria-01",
        },
    ).json()["data"]
    url = ROOT + "/operations/notifications/" + row["id"] + "/actions"
    assert client.post(url, headers=admin_headers, json={"action": "send"}).status_code == 409
    assert client.post(url, headers=admin_headers, json={"action": "test-send"}).status_code == 422
    assert (
        client.post(
            url,
            headers=admin_headers,
            json={"action": "test-send", "test_recipient_id": "admin-principal-test"},
        ).status_code
        == 422
    )
    assert (
        client.post(
            url,
            headers=auth_headers,
            json={"action": "test-send", "test_recipient_id": "admin-demo"},
        ).status_code
        == 401
    )
    assert (
        client.post(
            url,
            headers=admin_headers,
            json={"action": "test-send", "test_recipient_id": "admin-demo"},
        ).status_code
        == 200
    )
    with SessionLocal() as db:
        notices = db.scalars(select(NotificationInboxItem)).all()
        assert len(notices) == 1 and notices[0].category == "TEST"
        assert notices[0].user_id == "admin-demo"
    for act in ("submit", "approve", "send"):
        assert client.post(url, headers=admin_headers, json={"action": act}).status_code == 200
    assert client.post(url, headers=admin_headers, json={"action": "send"}).status_code == 409
    inbox = client.get("/api/v1/notifications/inbox", headers=auth_headers).json()["data"]["items"]
    assert len(inbox) == 1 and inbox[0]["title"] == "Catalog update"
    action(client, admin_headers, "card-aria-01", "offline")
    invalid = client.post(
        ROOT + "/operations/notifications",
        headers=admin_headers,
        json={"title": "No longer accessible", "target_type": "CARD", "target_id": "card-aria-01"},
    )
    assert invalid.status_code == 422


def test_published_card_pool_applies_to_real_draw(client, admin_headers, auth_headers):
    row = client.post(
        ROOT + "/operations/daily",
        headers=admin_headers,
        json={"title": "Only one card", "weights": {"card-aria-01": 100}},
    ).json()["data"]
    for act in ("submit", "approve"):
        assert (
            client.post(
                ROOT + "/operations/daily/" + row["id"] + "/actions",
                headers=admin_headers,
                json={"action": act},
            ).status_code
            == 200
        )
    drawn = client.post(
        "/api/v1/daily-cards/draw", headers=auth_headers, json={"draw_request_id": "pool-test"}
    ).json()["data"]["card"]
    assert drawn["id"] == "card-aria-01"
    exhausted = client.post(
        "/api/v1/daily-cards/draw", headers=auth_headers, json={"draw_request_id": "pool-test-2"}
    )
    assert exhausted.status_code == 409


def test_announcement_visibility_schedule_and_offline(client, admin_headers):
    row = client.post(
        ROOT + "/operations/announcements",
        headers=admin_headers,
        json={"title": "Homepage notice", "content": "Catalog has been updated", "priority": 5},
    ).json()["data"]
    assert client.get("/api/v1/announcements").json()["data"]["items"] == []
    url = ROOT + "/operations/announcements/" + row["id"] + "/actions"
    for act in ("submit", "approve"):
        assert client.post(url, headers=admin_headers, json={"action": act}).status_code == 200
    assert (
        client.get("/api/v1/announcements").json()["data"]["items"][0]["title"] == "Homepage notice"
    )
    assert client.post(url, headers=admin_headers, json={"action": "offline"}).status_code == 200
    assert client.get("/api/v1/announcements").json()["data"]["items"] == []


def test_admin_accounts_require_super_role_and_protect_current_account(client, admin_headers):
    created = client.post(
        ROOT + "/admins",
        headers=admin_headers,
        json={
            "account": "catalog-operator",
            "name": "Catalog Operator",
            "role": "content_operator",
            "password": "Independent-Test-Password1!",
            "reason": "创建测试管理员",
        },
    )
    assert created.status_code == 200
    admin_id = created.json()["data"]["id"]
    assert created.json()["data"]["account"] == "catalog-operator"
    token = client.post(
        "/api/v1/admin/auth/login",
        json={"account": "catalog-operator", "password": "Independent-Test-Password1!"},
    ).json()["data"]["access_token"]
    assert (
        client.get(ROOT + "/admins", headers={"Authorization": "Bearer " + token}).status_code
        == 403
    )
    current = client.get(ROOT + "/me", headers=admin_headers).json()["data"]["id"]
    assert (
        client.patch(
            ROOT + "/admins/" + current,
            headers=admin_headers,
            json={
                "role": "content_operator",
                "is_active": False,
                "expected_version": 1,
                "reason": "测试阻止停用自己",
            },
        ).status_code
        == 422
    )
    assert (
        client.patch(
            ROOT + "/admins/" + admin_id,
            headers=admin_headers,
            json={
                "role": "content_operator",
                "is_active": False,
                "expected_version": created.json()["data"]["version"],
                "reason": "测试停用",
            },
        ).status_code
        == 200
    )
    assert (
        client.get(ROOT + "/catalog", headers={"Authorization": "Bearer " + token}).status_code
        == 403
    )


def test_production_refuses_development_login(client, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "environment", "production")
    response = client.post(
        "/api/v1/auth/login", json={"method": "phone", "phone": "13900000000", "code": "666666"}
    )
    assert response.status_code == 400
    assert response.json()["error_code"] == "CHALLENGE_REQUIRED"
