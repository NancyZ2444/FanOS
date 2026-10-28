from uuid import uuid4

import pytest
from test_feedback_workflow import ADMIN, accept_and_publish, action, result

from app.core.database import SessionLocal
from app.models import Idol
from app.modules.admin import catalog_service
from app.modules.catalog import profiles

ROOT = "/api/v1/catalog/profiles/idols/idol-aria"
EDITOR = "/api/v1/admin/console/profiles/idols/idol-aria"


def proposal(client, headers, changes):
    obj = result(client.get("/api/v1/feedback/objects/idols/idol-aria", headers=headers))
    return result(
        client.post(
            "/api/v1/feedback",
            headers=headers,
            json={
                "kind": "CORRECTION",
                "entity_type": "idols",
                "entity_id": "idol-aria",
                "object_version": obj["version"],
                "request_key": str(uuid4()),
                "notes": "核对官方资料后的修订，来源为官方主页",
                "fields": changes,
            },
        )
    )


@pytest.mark.parametrize(
    "links",
    [
        ["test"],
        ["https://"],
        ["javascript:alert(1)"],
        ["https://example.com/has space"],
        ["https://person:secret@example.com"],
        ["https://example.com:99999/"],
        ["https://example.com/" + "x" * 800],
        ["https://example.com/"] * 7,
    ],
)
def test_profile_reference_validation_identifies_links_without_creating_revision(
    client, auth_headers, links
):
    obj = result(client.get("/api/v1/feedback/objects/idols/idol-aria", headers=auth_headers))
    response = client.post(
        "/api/v1/feedback",
        headers=auth_headers,
        json={
            "kind": "CORRECTION",
            "entity_type": "idols",
            "entity_id": "idol-aria",
            "object_version": obj["version"],
            "request_key": str(uuid4()),
            "fields": [
                {
                    "key": "career_text",
                    "mode": "SET",
                    "value": "官方已核实的从艺历程",
                    "reason": "补充遗漏",
                }
            ],
            "notes": "根据官方资料补充",
            "links": links,
        },
    )
    assert response.status_code == 422
    error = response.json()
    assert error["error_code"] == "VALIDATION_ERROR"
    assert any("links" in detail["loc"] for detail in error["data"]["details"])
    assert not result(client.get(ROOT + "/history"))["items"]
    assert not result(client.get("/api/v1/feedback", headers=auth_headers))["items"]


@pytest.mark.parametrize("links", [[], [" https://example.com/official-career "]])
def test_profile_career_with_valid_optional_reference_stays_pending_until_review(
    client, auth_headers, admin_headers, links
):
    obj = result(client.get("/api/v1/feedback/objects/idols/idol-aria", headers=auth_headers))
    before = next(f for f in obj["fields"] if f["key"] == "career_text")["current"]
    text = "2024年\n官方已核实的从艺历程"
    row = result(
        client.post(
            "/api/v1/feedback",
            headers=auth_headers,
            json={
                "kind": "CORRECTION",
                "entity_type": "idols",
                "entity_id": "idol-aria",
                "object_version": obj["version"],
                "request_key": str(uuid4()),
                "fields": [
                    {"key": "career_text", "mode": "SET", "value": text, "reason": "补充遗漏"}
                ],
                "notes": "根据官方资料补充",
                "links": links,
            },
        )
    )
    assert row["result"] == "PENDING"
    assert row["submission"]["links"] == [link.strip() for link in links]
    assert (
        next(f for f in result(client.get(ROOT))["fields"] if f["key"] == "career_text")["current"]
        == before
    )
    current = result(client.get(EDITOR, headers=admin_headers))
    final = result(
        accept_and_publish(
            client,
            admin_headers,
            row,
            object_version=current["version"],
            decisions=[{"key": "career_text", "decision": "ACCEPT"}],
        )
    )
    assert final["result"] == "INCLUDED"
    assert (
        next(f for f in result(client.get(ROOT))["fields"] if f["key"] == "career_text")["current"]
        == text
    )


def test_profile_invalid_field_value_reports_original_field(client, auth_headers):
    obj = result(client.get("/api/v1/feedback/objects/idols/idol-aria", headers=auth_headers))
    response = client.post(
        "/api/v1/feedback",
        headers=auth_headers,
        json={
            "kind": "CORRECTION",
            "entity_type": "idols",
            "entity_id": "idol-aria",
            "object_version": obj["version"],
            "request_key": str(uuid4()),
            "fields": [{"key": "career_text", "value": "字" * 20001}],
            "notes": "核对官方资料",
            "links": [],
        },
    )
    assert response.status_code == 422
    details = response.json()["data"]["details"]
    assert details[0]["field"] == "career_text"
    assert details[0]["loc"] == ["body", "fields", 0, "value"]


def test_dossier_fields_distinct_dates_and_legacy_text(client, auth_headers):
    with SessionLocal() as db:
        idol = db.get(Idol, "idol-aria")
        idol.careers = [{"period": "2020", "title": "阶段一", "subtitle": "第一行\n第二行"}]
        db.commit()
    obj = result(client.get(ROOT))
    values = {f["key"]: f["current"] for f in obj["fields"]}
    assert values["career_text"] == "2020\n阶段一\n第一行\n第二行"
    assert values["debut_date"] == ""
    assert "birth_date" in values
    assert "name_en" in values and "honors_text" in values
    group = result(client.get("/api/v1/catalog/profiles/groups/group-lumina"))
    assert not {"birth_date", "real_name", "gender"}.intersection(f["key"] for f in group["fields"])


def test_review_publish_long_text_history_privacy_and_no_draft_leak(
    client, auth_headers, admin_headers
):
    text = "2001年\n" + "核实正文" * 1200 + "\n\n结束"
    row = proposal(
        client,
        auth_headers,
        [{"key": "career_text", "value": text}, {"key": "debut_date", "value": "2020-03-12"}],
    )
    assert (
        next(f for f in result(client.get(ROOT))["fields"] if f["key"] == "career_text")["current"]
        != text
    )
    obj = result(client.get(EDITOR, headers=admin_headers))
    final = result(
        accept_and_publish(
            client,
            admin_headers,
            row,
            object_version=obj["version"],
            decisions=[{"key": k, "decision": "ACCEPT"} for k in ("career_text", "debut_date")],
        )
    )
    assert final["result"] == "INCLUDED"
    latest = result(client.get(ROOT))
    assert next(f for f in latest["fields"] if f["key"] == "career_text")["current"] == text
    history = result(client.get(ROOT + "/history"))["items"]
    assert len(history) == 1
    version = result(client.get(ROOT + "/history/" + history[0]["id"]))
    assert version["snapshot"]["career_text"] == text
    assert "submission_id" not in version and "legacy_careers" not in version
    assert version["author"]["id"] == "current-user"
    archive = result(client.get(EDITOR + "/history", headers=admin_headers))["items"]
    old = result(client.get(EDITOR + "/history/" + archive[-1]["id"], headers=admin_headers))
    assert old["snapshot"]["career_text"] != text


def test_editor_draft_atomic_conflict_and_idempotency(client, admin_headers):
    obj = result(client.get(EDITOR, headers=admin_headers))
    body = {
        "expected": obj["version"],
        "request_key": str(uuid4()),
        "summary": "核实出道日期",
        "values": {"debut_date": "2021-06-03"},
    }
    draft = result(client.put(EDITOR + "/draft", headers=admin_headers, json=body))
    assert (
        next(f for f in result(client.get(ROOT))["fields"] if f["key"] == "debut_date")["current"]
        == ""
    )
    body["draft_version"] = draft["draft_version"]
    published = result(client.post(EDITOR + "/publish", headers=admin_headers, json=body))
    assert (
        result(client.post(EDITOR + "/publish", headers=admin_headers, json=body))["id"]
        == published["id"]
    )
    result(
        client.post(
            EDITOR + "/publish", headers=admin_headers, json={**body, "request_key": str(uuid4())}
        ),
        409,
    )
    current = result(client.get(EDITOR, headers=admin_headers))
    result(
        client.post(
            EDITOR + "/publish",
            headers=admin_headers,
            json={
                **body,
                "expected": current["version"],
                "request_key": str(uuid4()),
                "values": {"honors_text": "不应保存", "name": ""},
            },
        ),
        422,
    )
    assert (
        next(f for f in result(client.get(ROOT))["fields"] if f["key"] == "honors_text")["current"]
        == ""
    )


def test_profile_permissions_unavailable_and_max_text(client, auth_headers, admin_headers):
    result(client.get(EDITOR, headers=auth_headers), 401)
    obj = result(client.get(EDITOR, headers=admin_headers))
    body = {
        "expected": obj["version"],
        "request_key": str(uuid4()),
        "summary": "说明",
        "values": {"career_text": "字" * 20001},
    }
    result(client.post(EDITOR + "/publish", headers=admin_headers, json=body), 422)
    with SessionLocal() as db:
        profiles.initialize(db, "idols", "idol-aria")
        meta = catalog_service.meta_for(db, "idols", "idol-aria")
        if meta is None:
            from app.admin_models import ContentMetadata

            meta = ContentMetadata(
                entity_type="idols",
                entity_id="idol-aria",
                status="OFFLINE",
                operator_id="admin-demo",
                data={},
            )
            db.add(meta)
        meta.status = "OFFLINE"
        db.commit()
    result(client.get(ROOT), 404)
    result(client.get(ROOT + "/history"), 404)


def editorial(client, headers, values, **extra):
    obj = result(client.get(EDITOR, headers=headers))
    return client.post(
        EDITOR + "/publish",
        headers=headers,
        json={
            "expected": obj["version"],
            "request_key": str(uuid4()),
            "summary": "平台核实官方资料",
            "values": values,
            **extra,
        },
    )


def test_field_conflict_and_unrelated_change_preservation(client, auth_headers, admin_headers):
    row = proposal(client, auth_headers, [{"key": "career_text", "value": "用户完整正文"}])
    result(editorial(client, admin_headers, {"debut_date": "2022-05-01"}))
    obj = result(client.get(EDITOR, headers=admin_headers))
    final = result(
        accept_and_publish(
            client,
            admin_headers,
            row,
            object_version=obj["version"],
            decisions=[{"key": "career_text", "decision": "ACCEPT"}],
        )
    )
    assert final["result"] == "INCLUDED"
    assert (
        next(f for f in result(client.get(ROOT))["fields"] if f["key"] == "debut_date")["current"]
        == "2022-05-01"
    )
    row = proposal(client, auth_headers, [{"key": "career_text", "value": "第二次建议"}])
    result(editorial(client, admin_headers, {"career_text": "最新平台正文"}))
    obj = result(client.get(EDITOR, headers=admin_headers))
    result(
        accept_and_publish(
            client,
            admin_headers,
            row,
            object_version=obj["version"],
            decisions=[{"key": "career_text", "decision": "ACCEPT"}],
        ),
        409,
    )
    row = result(client.get(ADMIN + "/" + row["id"], headers=admin_headers))
    assert row["review_decision"] == "ACCEPTED"
    result(
        accept_and_publish(
            client,
            admin_headers,
            row,
            object_version=obj["version"],
            decisions=[
                {
                    "key": "career_text",
                    "decision": "MODIFY",
                    "value": "核对后的合并全文",
                    "reason": "保留最新已核实部分",
                }
            ],
        )
    )


def test_noop_image_edit_without_provenance_and_account_permissions(
    client, auth_headers, admin_headers
):
    before = result(client.get(ROOT))
    name = next(f for f in before["fields"] if f["key"] == "name")["current"]
    result(editorial(client, admin_headers, {"name": name}), 422)
    assert not result(client.get(ROOT + "/history"))["items"]
    result(editorial(client, admin_headers, {"image_url": "https://example.com/authorized.png"}))
    with SessionLocal() as db:
        from app.auth_models import AdminPrincipal
        from app.core.security import secret_hash

        db.add(
            AdminPrincipal(
                account="profile-operator",
                display_name="内容运营",
                role="content_operator",
                password_hash=secret_hash("Profile-Operator-123"),
            )
        )
        db.commit()
    token = result(
        client.post(
            "/api/v1/admin/auth/login",
            json={"account": "profile-operator", "password": "Profile-Operator-123"},
        )
    )["access_token"]
    operator_headers = {"Authorization": "Bearer " + token}
    result(client.get(EDITOR, headers=operator_headers))
    result(editorial(client, operator_headers, {"honors_text": "不应生效"}), 403)


def test_membership_changes_are_versioned_on_both_sides_and_atomic(client, admin_headers):
    fields = result(client.get(ROOT))["fields"]
    member = next(f for f in fields if f["key"] == "memberships")["current"][0]
    target = "/api/v1/catalog/profiles/groups/" + member["target_id"]
    operation = {
        "operation": "UPDATE",
        "id": member["id"],
        "data": {
            k: member.get(k, "") for k in ("target_id", "start_date", "end_date", "status", "role")
        },
    }
    operation["data"]["role"] = "主唱"
    result(editorial(client, admin_headers, {"memberships": [operation]}))
    assert not result(client.get(target + "/history"))["items"]
    assert (
        len(
            result(
                client.get(
                    target.replace("/catalog/", "/admin/console/") + "/history",
                    headers=admin_headers,
                )
            )["items"]
        )
        == 2
    )
    assert not result(client.get(ROOT + "/history"))["items"]
    assert len(result(client.get(EDITOR + "/history", headers=admin_headers))["items"]) == 2
    response = editorial(
        client,
        admin_headers,
        {
            "honors_text": "不能先写入",
            "memberships": [{"operation": "DELETE", "id": member["id"], "reason": "核实原关系"}],
        },
    )
    result(response, 409)
    current = result(client.get(ROOT))
    assert next(f for f in current["fields"] if f["key"] == "honors_text")["current"] == ""
    assert not result(client.get(ROOT + "/history"))["items"]
    assert len(result(client.get(EDITOR + "/history", headers=admin_headers))["items"]) == 2


def test_submission_attribution_snapshot_filters_and_pending_privacy(
    client, auth_headers, admin_headers
):
    row = proposal(client, auth_headers, [{"key": "honors_text", "value": "经核实的完整荣誉正文"}])
    assert result(client.get(ROOT))["pending_feedback_id"] is None
    assert result(client.get(ROOT, headers=auth_headers))["pending_feedback_id"] == row["id"]
    queue = "/api/v1/admin/console/feedback?kind=CORRECTION&profile_only=true&section_key="
    assert len(result(client.get(queue + "honors", headers=admin_headers))["items"]) == 1
    assert not result(client.get(queue + "career", headers=admin_headers))["items"]
    with SessionLocal() as db:
        from app.models import User

        old_name = db.get(User, "current-user").display_name
        db.get(User, "current-user").display_name = "提交后改过的昵称"
        db.commit()
    obj = result(client.get(EDITOR, headers=admin_headers))
    final = result(
        accept_and_publish(
            client,
            admin_headers,
            row,
            object_version=obj["version"],
            decisions=[{"key": "honors_text", "decision": "ACCEPT"}],
        )
    )
    published = result(client.get(ROOT + "/history/" + final["profile_version"]))
    assert published["author"]["name"] == old_name


def test_profile_resubmit_preserves_old_batch_and_rejects_foreign_relation_id(
    client, auth_headers, admin_headers
):
    row = proposal(client, auth_headers, [{"key": "honors_text", "value": "第一批正文"}])
    requested = result(
        action(client, admin_headers, row, "need_info", public_note="请补充官方出处")
    )
    assert requested["can_resubmit"]
    obj = result(client.get(EDITOR, headers=admin_headers))
    body = {
        "kind": "CORRECTION",
        "entity_type": "idols",
        "entity_id": "idol-aria",
        "revision": requested["revision"],
        "object_version": obj["version"],
        "request_key": str(uuid4()),
        "notes": "已补充官方出处",
        "fields": [{"key": "honors_text", "value": "第二批核实正文"}],
    }
    endpoint = f"/api/v1/feedback/records/{row['id']}/resubmit"
    submitted = result(client.post(endpoint, headers=auth_headers, json=body))
    assert submitted["id"] == row["id"] and submitted["result"] == "PENDING"
    assert (
        submitted["submission"]["previous_submissions"][0]["submission"]["fields"][0]["suggested"]
        == "第一批正文"
    )
    assert (
        result(client.post(endpoint, headers=auth_headers, json=body))["revision"]
        == submitted["revision"]
    )
    result(
        editorial(
            client,
            admin_headers,
            {"memberships": [{"operation": "ADD", "id": "foreign-id", "data": {}}]},
        ),
        422,
    )
    assert not result(client.get(ROOT + "/history"))["items"]


def test_overlimit_legacy_content_and_distinct_relationship_suggestions(client, admin_headers):
    with SessionLocal() as db:
        row = db.get(Idol, "idol-aria")
        row.careers = [{"period": "原时间", "title": "旧正文", "subtitle": "保留" * 11000}]
        db.commit()
    current = result(client.get(ROOT))
    field = next(f for f in current["fields"] if f["key"] == "career_text")
    assert field["max_length"] == len(field["current"]) > 20000
    result(
        editorial(client, admin_headers, {"career_text": field["current"] + "不能继续增长"}), 422
    )
    result(editorial(client, admin_headers, {"career_text": "整理后的正文"}))
    initial = result(client.get(EDITOR + "/history", headers=admin_headers))["items"][-1]
    assert (
        result(client.get(EDITOR + "/history/" + initial["id"], headers=admin_headers))["snapshot"][
            "career_text"
        ]
        == field["current"]
    )
    a = [
        {
            "key": "memberships",
            "type": "relations",
            "mode": "SET",
            "suggested": [{"operation": "UPDATE", "id": "m1"}],
        }
    ]
    b = [
        {
            "key": "memberships",
            "type": "relations",
            "mode": "SET",
            "suggested": [{"operation": "UPDATE", "id": "m2"}],
        }
    ]
    assert not profiles.overlapping_suggestions(a, b)
    assert profiles.overlapping_suggestions(a, a)
