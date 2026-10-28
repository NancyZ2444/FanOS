"""Review decisions are public; publication only applies the submitted approval."""

from uuid import uuid4

import pytest
from sqlalchemy import select
from test_feedback_workflow import ADMIN, ROOT, action, correction, missing, result, upload
from test_missing_catalog_feedback import body as catalog_body

from app.core.database import SessionLocal
from app.future_models import NotificationInboxItem
from app.models import Card, CatalogAlbum
from app.modules.feedback.models import Feedback


def fetch(client, headers, row, admin=False):
    return result(
        client.get(f"{ADMIN if admin else ROOT + '/records'}/{row['id']}", headers=headers)
    )


def decide(client, headers, row, decision="ACCEPTED", **values):
    return action(client, headers, row, "decide", review_decision=decision, **values)


def notice_count():
    with SessionLocal() as db:
        return len(list(db.scalars(select(NotificationInboxItem))))


def test_accept_is_public_without_publishing_and_publish_uses_snapshot(
    client, auth_headers, admin_headers
):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    result(action(client, admin_headers, row, "publish"), 409)
    before = notice_count()
    approved = result(
        decide(client, admin_headers, row, changes={"title": "已确认小卡"}, internal_note="仅后台")
    )
    assert approved["review_decision"] == "ACCEPTED" and approved["can_publish"]
    assert approved["entity_id"] == "" and approved["result"] == "PENDING"
    public = fetch(client, auth_headers, row)
    assert public["status_label"] == "已采纳，待发布"
    assert public["public_note"] == "已核对提交内容"
    assert public["history"][-1]["action"] == "decide"
    assert "review" not in public and "internal_note" not in public
    assert notice_count() == before + 1
    result(action(client, admin_headers, approved, "publish", changes={"title": "未审核替换"}), 409)
    published = result(action(client, admin_headers, approved, "publish"))
    assert published["result"] == "INCLUDED" and not published["can_publish"]
    assert published["internal_note"] == "仅后台"
    with SessionLocal() as db:
        card = db.get(Card, published["entity_id"])
        assert card.title == "已确认小卡" and card.status == "PUBLISHED"
    assert notice_count() == before + 2


def test_private_draft_invalidates_approval_without_public_update(
    client, auth_headers, admin_headers
):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    approved = result(decide(client, admin_headers, row))
    before = fetch(client, auth_headers, row)
    count = notice_count()
    draft = result(
        action(
            client,
            admin_headers,
            approved,
            "draft",
            changes={"title": "再次修改"},
            review_decision="REJECTED",
            public_note="内部拟定",
        )
    )
    assert not draft["can_publish"] and draft["review_decision"] is None
    assert draft["review"]["review_decision_draft"] == "REJECTED"
    current = fetch(client, auth_headers, row)
    for key in ["status", "status_label", "public_note", "history", "updated_at"]:
        assert current[key] == before[key]
    assert notice_count() == count
    result(action(client, admin_headers, draft, "publish"), 409)


@pytest.mark.parametrize("kind", ["MISSING_CARD", "CORRECTION", "MISSING_CATALOG"])
@pytest.mark.parametrize(
    "decision,expected", [("REJECTED", "NOT_INCLUDED"), ("NEEDS_INFO", "NEEDS_INFO")]
)
def test_terminal_decisions_require_note_and_never_publish(
    client, auth_headers, admin_headers, kind, decision, expected
):
    body = (
        missing(client, auth_headers)
        if kind == "MISSING_CARD"
        else correction(client, auth_headers)
        if kind == "CORRECTION"
        else catalog_body("groups", name="New group")
    )
    row = result(client.post(ROOT, headers=auth_headers, json=body))
    result(decide(client, admin_headers, row, decision, public_note="  "), 422)
    decided = result(decide(client, admin_headers, row, decision, public_note="请查看处理说明"))
    assert decided["result"] == expected and not decided["can_publish"]
    result(action(client, admin_headers, decided, "publish"), 409)
    public = fetch(client, auth_headers, row)
    assert public["submission"] == row["submission"]
    assert public["public_note"] == "请查看处理说明"
    if decision == "NEEDS_INFO":
        retried = result(
            client.post(
                f"{ROOT}/records/{row['id']}/resubmit",
                headers=auth_headers,
                json={
                    **body,
                    "revision": decided["revision"],
                    "request_key": str(uuid4()),
                    "notes": "补充说明",
                },
            )
        )
        assert retried["id"] == row["id"] and retried["result"] == "PENDING"
        admin = fetch(client, admin_headers, row, True)
        assert not admin["can_publish"] and admin["review_decision"] is None


def test_correction_two_phase_and_changed_target_conflict(client, auth_headers, admin_headers):
    submission = correction(client, auth_headers)
    row = result(client.post(ROOT, headers=auth_headers, json=submission))
    approved = result(
        decide(
            client,
            admin_headers,
            row,
            decisions=[{"key": "name", "decision": "ACCEPT"}],
            object_version=submission["object_version"],
        )
    )
    with SessionLocal() as db:
        album = db.get(CatalogAlbum, "album-starlit")
        assert album.name != "Corrected Album"
        album.name = "他人已修改"
        db.commit()
    result(action(client, admin_headers, approved, "publish"), 409)
    obj = result(client.get(ROOT + "/objects/albums/album-starlit", headers=auth_headers))
    approved = result(
        decide(
            client,
            admin_headers,
            approved,
            decisions=[{"key": "name", "decision": "MODIFY", "value": "重新核实的名称"}],
            object_version=obj["version"],
        )
    )
    published = result(action(client, admin_headers, approved, "publish"))
    assert published["result"] == "INCLUDED"
    with SessionLocal() as db:
        assert db.get(CatalogAlbum, "album-starlit").name == "重新核实的名称"


def test_missing_catalog_approved_upload_is_published(client, auth_headers, admin_headers):
    image = upload(client, auth_headers)
    row = result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=catalog_body("groups", name="New group", image_url=image["id"]),
        )
    )
    approved = result(decide(client, admin_headers, row, changes={"name": "核实后名称"}))
    assert approved["entity_id"] == ""
    published = result(action(client, admin_headers, approved, "publish"))
    assert published["result"] == "INCLUDED" and published["target_available"]


def test_decision_retry_version_permission_and_failure_atomicity(
    client, auth_headers, admin_headers, admin_actor_headers
):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    editor = admin_actor_headers("content_operator", "decision-editor")
    result(decide(client, editor, row), 403)
    body = {
        "action": "decide",
        "review_decision": "ACCEPTED",
        "revision": row["revision"],
        "request_key": str(uuid4()),
        "public_note": "已采纳",
        "changes": {"source_entity_id": "missing-source"},
    }
    endpoint = f"{ADMIN}/{row['id']}/actions"
    approved = result(client.post(endpoint, headers=admin_headers, json=body))
    assert (
        result(client.post(endpoint, headers=admin_headers, json=body))["revision"]
        == approved["revision"]
    )
    result(
        client.post(endpoint, headers=admin_headers, json={**body, "public_note": "不同内容"}), 409
    )
    count = notice_count()
    failed = action(client, admin_headers, approved, "publish")
    result(failed, 422)
    after = fetch(client, admin_headers, row, True)
    assert after["revision"] == approved["revision"] and not after["entity_id"]
    assert after["can_publish"] and notice_count() == count
    with SessionLocal() as db:
        assert (
            db.get(Feedback, row["id"]).review["approved_payload"]
            == approved["review"]["approved_payload"]
        )


def test_full_editor_cannot_bypass_feedback_decision(client, auth_headers, admin_headers):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    draft = result(action(client, admin_headers, row, "draft"))
    endpoint = f"/api/v1/admin/console/cards/{draft['entity_id']}/actions"
    result(client.post(endpoint, headers=admin_headers, json={"action": "submit"}))
    result(client.post(endpoint, headers=admin_headers, json={"action": "publish"}), 409)
    with SessionLocal() as db:
        assert db.get(Card, draft["entity_id"]).status != "PUBLISHED"
    approved = result(decide(client, admin_headers, draft))
    published = result(action(client, admin_headers, approved, "publish"))
    assert published["result"] == "INCLUDED"
    with SessionLocal() as db:
        assert db.get(Card, draft["entity_id"]).status == "PUBLISHED"


def test_resubmitted_catalog_replaces_old_internal_draft(client, auth_headers, admin_headers):
    old_image = upload(client, auth_headers)
    submission = catalog_body("groups", name="Original group", image_url=old_image["id"])
    row = result(client.post(ROOT, headers=auth_headers, json=submission))
    draft = result(
        action(client, admin_headers, row, "draft", changes={"name": "Old private draft"})
    )
    requested = result(
        decide(client, admin_headers, draft, "NEEDS_INFO", public_note="请补充新图和名称")
    )
    new_image = upload(client, auth_headers)
    supplement = catalog_body("groups", name="Updated group", image_url=new_image["id"])
    resubmitted = result(
        client.post(
            f"{ROOT}/records/{row['id']}/resubmit",
            headers=auth_headers,
            json={**supplement, "revision": requested["revision"]},
        )
    )
    admin = fetch(client, admin_headers, row, True)
    assert "catalog_draft" not in admin["review"]
    assert admin["review"]["previous_catalog_drafts"][0]["name"] == "Old private draft"
    approved = result(decide(client, admin_headers, resubmitted))
    published = result(action(client, admin_headers, approved, "publish"))
    obj = result(
        client.get(ROOT + f"/objects/groups/{published['entity_id']}", headers=auth_headers)
    )
    assert obj["name"] == "Updated group" and obj["image_url"] == new_image["image_url"]


def test_decision_schema_supports_all_submission_fields():
    from app.modules.feedback.router import Action, Submission

    count = Submission.model_fields["fields"].metadata[-1].max_length
    assert count == 30
    parsed = Action(
        request_key=str(uuid4()),
        revision=1,
        action="decide",
        review_decision="ACCEPTED",
        decisions=[{"key": str(i), "decision": "ACCEPT"} for i in range(count)],
    )
    assert len(parsed.decisions) == count
