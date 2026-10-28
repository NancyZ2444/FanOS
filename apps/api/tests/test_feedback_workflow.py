from io import BytesIO
from uuid import uuid4

from PIL import Image
from sqlalchemy import select

from app.admin_models import CardImageVersion
from app.core.database import SessionLocal
from app.models import Card, DetectedCard, ScanSession
from app.modules.feedback.models import CardContribution, FeedbackNotice

ROOT = "/api/v1/feedback"
ADMIN = "/api/v1/admin/console/feedback"


def result(response, status=200):
    assert response.status_code == status, response.text
    return response.json().get("data")


def upload(client, headers):
    output = BytesIO()
    Image.new("RGB", (150, 210), "navy").save(output, "PNG")
    return result(
        client.post(
            ROOT + "/images",
            headers=headers,
            files={"file": ("test.png", output.getvalue(), "image/png")},
        )
    )


def missing(client, headers, **extra):
    image = upload(client, headers)
    with SessionLocal() as db:
        session = ScanSession(user_id="current-user", original_image_url=image["image_url"])
        db.add(session)
        db.flush()
        crop = DetectedCard(
            scan_session_id=session.id,
            crop_image_url=image["image_url"],
            crop_region={"x": 0, "y": 0, "width": 1, "height": 1},
            recognition_status="unrecognized",
        )
        db.add(crop)
        db.commit()
        values = {
            "scan_session_id": session.id,
            "detected_card_id": crop.id,
            "group_id": "group-lumina",
            "idol_id": "idol-aria",
            "source_entity_type": "ALBUM",
            "source_entity_id": "album-starlit",
            **extra,
        }
    body = {"kind": "MISSING_CARD", "request_key": str(uuid4()), "missing": values}
    return body


def correction(client, headers, **extra):
    obj = result(client.get(ROOT + "/objects/albums/album-starlit", headers=headers))
    return {
        "kind": "CORRECTION",
        "request_key": str(uuid4()),
        "entity_type": "albums",
        "entity_id": "album-starlit",
        "object_version": obj["version"],
        "fields": [{"key": "name", "value": "Corrected Album"}],
        **extra,
    }


def action(client, headers, row, verb, **extra):
    body = {
        "action": verb,
        "revision": row["revision"],
        "request_key": str(uuid4()),
        **({"public_note": "已核对提交内容"} if verb != "publish" else {}),
        **extra,
    }
    return client.post(f"{ADMIN}/{row['id']}/actions", headers=headers, json=body)


def accept(client, headers, row, **extra):
    """Submit an explicit public approval, preserving the supplied review snapshot."""
    return result(action(client, headers, row, "decide", review_decision="ACCEPTED", **extra))


def accept_and_publish(client, headers, row, **extra):
    accepted = accept(client, headers, row, **extra)
    return action(client, headers, accepted, "publish")


def test_missing_idempotency_authentic_context_and_private_details(
    client, auth_headers, second_app_headers
):
    body = missing(client, auth_headers)
    row = result(client.post(ROOT, headers=auth_headers, json=body))
    again = result(client.post(ROOT, headers=auth_headers, json=body))
    assert again["id"] == row["id"]
    assert row["status_label"] == "待处理"
    assert row["submission"]["scan"]["detected_card_id"] == body["missing"]["detected_card_id"]
    assert "internal_note" not in row
    assert "request_hash" not in row["submission"]
    result(client.get(ROOT + "/records/" + row["id"], headers=second_app_headers), 404)
    result(client.post(ROOT, headers=auth_headers, json={**body, "notes": "different"}), 409)
    result(
        client.post(ROOT, headers=second_app_headers, json={**body, "request_key": str(uuid4())}),
        404,
    )


def test_scan_clue_optional_metadata_keeps_trusted_context_and_review_rules(
    client, auth_headers, second_app_headers, admin_headers
):
    body = missing(
        client,
        auth_headers,
        feedback_mode="SCAN_CLUE",
        group_id=None,
        idol_id=None,
        source_entity_type=None,
        source_entity_id=None,
    )
    body["missing"]["original_image_url"] = "https://untrusted.invalid/fake.jpg"
    row = result(client.post(ROOT, headers=auth_headers, json=body))
    assert row["submission"]["missing"]["feedback_mode"] == "SCAN_CLUE"
    assert row["submission"]["scan"]["detected_card_id"] == body["missing"]["detected_card_id"]
    assert row["submission"]["scan"]["original_image_url"] != body["missing"]["original_image_url"]
    assert row["submission"]["front"]["image_url"] == row["submission"]["scan"]["crop_image_url"]
    assert result(client.post(ROOT, headers=auth_headers, json=body))["id"] == row["id"]
    result(client.post(ROOT, headers=second_app_headers, json=body), 404)
    result(client.get(ADMIN + "/" + row["id"], headers=admin_headers))
    accepted = accept(client, admin_headers, row)
    result(action(client, admin_headers, accepted, "publish"), 422)
    draft = result(
        action(
            client,
            admin_headers,
            accepted,
            "draft",
            changes={
                "group_id": "group-lumina",
                "idol_id": "idol-aria",
                "source_entity_type": "ALBUM",
                "source_entity_id": "album-starlit",
            },
        )
    )
    published = result(accept_and_publish(client, admin_headers, draft))
    assert published["draft"]["front_source"]["copyright_status"] == "UNKNOWN"
    with SessionLocal() as db:
        assert db.get(Card, draft["entity_id"]).status == "PUBLISHED"
    for invalid in [
        {"group_id": "not-a-group"},
        {"idol_id": "not-an-idol"},
        {"source_entity_type": "UNKNOWN"},
        {"source_entity_id": "not-an-album"},
        {"source_version_id": "orphan-version"},
    ]:
        response = client.post(
            ROOT,
            headers=auth_headers,
            json={
                **body,
                "request_key": str(uuid4()),
                "missing": {**body["missing"], **invalid},
            },
        )
        assert response.status_code in {400, 404, 422}, response.text


def test_missing_required_relations_double_side_and_reason(client, auth_headers, admin_headers):
    body = missing(client, auth_headers)
    for patch in [
        {"group_id": None},
        {"idol_id": None},
        {"source_entity_id": None},
        {"is_double_sided": True},
    ]:
        result(
            client.post(
                ROOT,
                headers=auth_headers,
                json={**body, "request_key": str(uuid4()), "missing": {**body["missing"], **patch}},
            ),
            422,
        )
    row = result(client.post(ROOT, headers=auth_headers, json=body))
    result(action(client, admin_headers, row, "reject", public_note=""), 422)
    rejected = result(
        action(client, admin_headers, row, "reject", public_note="图片不清晰，请补充无遮挡正面")
    )
    assert rejected["status_label"] == "无法采用"
    assert rejected["result"] == "NOT_INCLUDED"


def test_draft_then_publish_contribution_and_notification_once(client, auth_headers, admin_headers):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    draft = result(action(client, admin_headers, row, "draft"))
    assert draft["status_label"] == "处理中" and draft["result"] == "PENDING"
    draft2 = result(action(client, admin_headers, draft, "draft"))
    assert draft2["entity_id"] == draft["entity_id"]
    assert result(client.get(ROOT + "/users/me/contributions", headers=auth_headers))["total"] == 0
    assert draft2["draft"]["front_source"]["copyright_status"] == "UNKNOWN"
    current = result(client.get(ADMIN + "/" + row["id"], headers=admin_headers))
    current = accept(client, admin_headers, current, public_note="图片已采纳，待发布")
    body = {
        "action": "publish",
        "revision": current["revision"],
        "request_key": str(uuid4()),
    }
    published = result(
        client.post(ADMIN + "/" + row["id"] + "/actions", headers=admin_headers, json=body)
    )
    assert published["result"] == "INCLUDED"
    assert (
        result(client.post(ADMIN + "/" + row["id"] + "/actions", headers=admin_headers, json=body))[
            "revision"
        ]
        == published["revision"]
    )
    credits = result(client.get(ROOT + f"/cards/{draft['entity_id']}/contributors"))["items"]
    assert credits[0]["user_id"] == "current-user"
    assert result(client.get(ROOT + "/users/me/contributions", headers=auth_headers))["total"] == 1
    with SessionLocal() as db:
        versions = db.scalars(
            select(CardImageVersion).where(CardImageVersion.card_id == draft["entity_id"])
        ).all()
        assert versions[-1].data["source_type"] == "USER_SUBMITTED"
        assert versions[-1].data["version_identity"] == "OFFICIAL_CATALOG"
        assert versions[-1].data["submissions"][0]["feedback_id"] == row["id"]
        assert len(db.scalars(select(CardContribution)).all()) == 1
        assert all(n.delivered for n in db.scalars(select(FeedbackNotice)))
    messages = result(client.get("/api/v1/notifications/inbox", headers=auth_headers))["items"]
    included = [m for m in messages if m["title"] == "反馈已采用"]
    assert len(included) == 1
    assert len(messages) == 2  # Approval and publication are separate public updates.
    result(
        client.post(
            f"/api/v1/admin/console/cards/{draft['entity_id']}/actions",
            headers=admin_headers,
            json={"action": "offline"},
        )
    )
    assert result(client.get(ROOT + "/users/me/contributions", headers=auth_headers))["total"] == 0
    history = result(client.get(ROOT + "/records/" + row["id"], headers=auth_headers))
    assert history["result"] == "INCLUDED" and not history["target_available"]


def test_correction_snapshot_partial_publish_no_text_credit(client, auth_headers, admin_headers):
    body = correction(
        client,
        auth_headers,
        fields=[
            {"key": "name", "value": "Updated title"},
            {"key": "description", "mode": "UNKNOWN", "reason": "介绍缺少发行说明"},
        ],
    )
    row = result(client.post(ROOT, headers=auth_headers, json=body))
    before = result(client.get(ROOT + "/objects/albums/album-starlit", headers=auth_headers))
    decisions = [
        {"key": "name", "decision": "ACCEPT"},
        {"key": "description", "decision": "REJECT", "reason": "已核实原介绍准确"},
    ]
    reviewed = result(
        action(
            client,
            admin_headers,
            row,
            "review",
            decisions=decisions,
            internal_note="internal secret",
        )
    )
    assert reviewed["result"] == "PENDING"
    assert (
        result(client.get(ROOT + "/objects/albums/album-starlit", headers=auth_headers))["version"]
        == before["version"]
    )
    published = result(
        accept_and_publish(
            client,
            admin_headers,
            reviewed,
            decisions=decisions,
            object_version=before["version"],
        )
    )
    assert published["result"] == "INCLUDED"
    public = result(client.get(ROOT + "/records/" + row["id"], headers=auth_headers))
    assert "internal secret" not in str(public)
    assert public["submission"]["object"]["name"] == before["name"]
    assert len(public["decisions"]) == 2
    assert result(client.get(ROOT + "/users/me/contributions", headers=auth_headers))["total"] == 0


def test_correction_invalid_field_unchanged_and_conflicting_version(
    client, auth_headers, admin_headers
):
    body = correction(client, auth_headers)
    for patch in [
        {"fields": [{"key": "operator", "value": "evil"}]},
        {"fields": [{"key": "name", "value": "Starlit"}]},
        {"fields": [{"key": "name", "mode": "UNKNOWN"}]},
    ]:
        result(client.post(ROOT, headers=auth_headers, json={**body, **patch}), 422)
    row = result(client.post(ROOT, headers=auth_headers, json=body))
    result(action(client, admin_headers, row, "draft"), 422)
    result(
        accept_and_publish(
            client,
            admin_headers,
            row,
            object_version="old",
            decisions=[{"key": "name", "decision": "ACCEPT"}],
        ),
        409,
    )
    result(action(client, auth_headers, row, "publish", object_version=body["object_version"]), 401)


def test_correction_multi_field_rollback_and_no_inclusion_notice(
    client, auth_headers, admin_headers
):
    body = correction(
        client,
        auth_headers,
        fields=[
            {"key": "name", "value": "Never published"},
            {"key": "release_date", "value": "2026-01-01"},
        ],
    )
    row = result(client.post(ROOT, headers=auth_headers, json=body))
    accepted = accept(
        client,
        admin_headers,
        row,
        object_version=body["object_version"],
        decisions=[
            {"key": "name", "decision": "ACCEPT"},
            {"key": "release_date", "decision": "MODIFY", "value": "invalid-date"},
        ],
    )
    result(action(client, admin_headers, accepted, "publish"), 422)
    obj = result(client.get(ROOT + "/objects/albums/album-starlit", headers=auth_headers))
    assert obj["version"] == body["object_version"]
    current = result(client.get(ROOT + "/records/" + row["id"], headers=auth_headers))
    assert current["result"] == "PENDING"
    assert current["status_label"] == "已采纳，待发布"
    assert current["revision"] == accepted["revision"]
    assert not any(
        m["title"] == "反馈已采用"
        for m in result(client.get("/api/v1/notifications/inbox", headers=auth_headers))["items"]
    )


def test_image_ownership_and_crop_validation(client, auth_headers, second_app_headers):
    asset = upload(client, second_app_headers)
    body = correction(client, auth_headers, fields=[{"key": "image_url", "value": asset["id"]}])
    result(client.post(ROOT, headers=auth_headers, json=body), 422)
    result(
        client.post(
            ROOT + "/images",
            headers=auth_headers,
            files={"file": ("fake.png", b"not an image", "image/png")},
        ),
        422,
    )


def test_match_existing_does_not_give_credit(client, auth_headers, admin_headers):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    matched = result(
        action(
            client,
            admin_headers,
            row,
            "match",
            card_id="card-aria-01",
            public_note="图鉴已有对应小卡，本次是识别匹配问题",
        )
    )
    assert matched["result"] == "NOT_INCLUDED"
    assert matched["target_available"]
    assert result(client.get(ROOT + "/users/me/contributions", headers=auth_headers))["total"] == 0


def test_missing_source_can_save_draft_but_not_publish(client, auth_headers, admin_headers):
    row = result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=missing(
                client, auth_headers, source_entity_id=None, missing_source_name="尚未录入的专辑"
            ),
        )
    )
    draft = result(action(client, admin_headers, row, "draft"))
    assert draft["entity_id"]
    accepted = accept(client, admin_headers, draft)
    result(action(client, admin_headers, accepted, "publish"), 422)
    with SessionLocal() as db:
        assert db.get(Card, draft["entity_id"]).status == "DRAFT"


def test_full_editor_cannot_publish_pending_feedback(client, auth_headers, admin_headers):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    draft = result(
        action(
            client,
            admin_headers,
            row,
            "draft",
            changes={
                "front_source": {"source_type": "USER_SUBMITTED", "copyright_status": "AUTHORIZED"}
            },
        )
    )
    path = f"/api/v1/admin/console/cards/{draft['entity_id']}/actions"
    result(client.post(path, headers=admin_headers, json={"action": "submit"}))
    result(client.post(path, headers=admin_headers, json={"action": "publish"}), 409)
    assert (
        result(client.get(ROOT + "/records/" + row["id"], headers=auth_headers))["result"]
        == "PENDING"
    )
    assert result(client.get(ROOT + "/users/me/contributions", headers=auth_headers))["total"] == 0
    with SessionLocal() as db:
        assert db.get(Card, draft["entity_id"]).status == "PENDING"


def test_card_image_correction_creates_only_real_image_contribution(
    client, auth_headers, admin_headers
):
    with SessionLocal() as db:
        card = db.get(Card, "card-aria-01")
        card.admin_data = {
            **card.admin_data,
            "source_entity_type": "ALBUM",
            "source_entity_id": "album-starlit",
        }
        db.commit()
    asset = upload(client, auth_headers)
    obj = result(client.get(ROOT + "/objects/cards/card-aria-01", headers=auth_headers))
    row = result(
        client.post(
            ROOT,
            headers=auth_headers,
            json={
                "kind": "CORRECTION",
                "entity_type": "cards",
                "entity_id": "card-aria-01",
                "object_version": obj["version"],
                "request_key": str(uuid4()),
                "fields": [{"key": "image_url", "value": asset["id"]}],
            },
        )
    )
    published = result(
        accept_and_publish(
            client,
            admin_headers,
            row,
            object_version=obj["version"],
            decisions=[{"key": "image_url", "decision": "ACCEPT"}],
            sources={"front_source": {"copyright_status": "AUTHORIZED"}},
        )
    )
    assert published["result"] == "INCLUDED"
    assert result(client.get(ROOT + "/users/me/contributions", headers=auth_headers))["total"] == 1


def test_new_migration_creates_feedback_tables_without_touching_legacy_data(tmp_path):
    import importlib.util
    from pathlib import Path

    from alembic.migration import MigrationContext
    from alembic.operations import Operations
    from sqlalchemy import create_engine, inspect

    engine = create_engine(f"sqlite:///{tmp_path / 'migration.db'}")
    file = Path(__file__).parents[1] / "migrations/versions/g614_feedback_workflow.py"
    spec = importlib.util.spec_from_file_location("feedback_migration", file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with engine.begin() as conn:
        conn.exec_driver_sql("CREATE TABLE users (id VARCHAR(64) PRIMARY KEY)")
        conn.exec_driver_sql("CREATE TABLE cards (id VARCHAR(64) PRIMARY KEY)")
        conn.exec_driver_sql("CREATE TABLE card_image_versions (id VARCHAR(64) PRIMARY KEY)")
        conn.exec_driver_sql("INSERT INTO users VALUES ('keep-user')")
        with Operations.context(MigrationContext.configure(conn)):
            module.upgrade()
        assert "catalog_card_contributions" in inspect(conn).get_table_names()
        assert conn.exec_driver_sql("SELECT id FROM users").scalar_one() == "keep-user"


def test_notice_failure_retries_without_reverting_review(
    client, auth_headers, admin_headers, monkeypatch
):
    from app.modules.feedback import service

    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    actual = service.deliver_notices
    monkeypatch.setattr(service, "deliver_notices", lambda *args: None)
    result(action(client, admin_headers, row, "reject", public_note="图片不够清楚，请重新补充"))
    with SessionLocal() as db:
        assert not db.scalars(select(FeedbackNotice)).first().delivered
    monkeypatch.setattr(service, "deliver_notices", actual)
    first = result(client.get("/api/v1/notifications/inbox", headers=auth_headers))["items"]
    second = result(client.get("/api/v1/notifications/inbox", headers=auth_headers))["items"]
    assert len(first) == len(second) == 1
