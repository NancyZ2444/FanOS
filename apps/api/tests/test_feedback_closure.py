from uuid import uuid4

from sqlalchemy import select
from test_feedback_workflow import (
    ADMIN,
    ROOT,
    accept,
    accept_and_publish,
    action,
    correction,
    missing,
    result,
    upload,
)

from app.core.database import SessionLocal
from app.future_models import NotificationInboxItem
from app.models import Card, CatalogAlbum
from app.modules.feedback.models import Feedback, FeedbackNotice


def user_detail(client, headers, row):
    return result(client.get(f"{ROOT}/records/{row['id']}", headers=headers))


def user_state(row):
    return {
        key: row[key]
        for key in ("status", "result", "status_label", "public_note", "history", "updated_at")
    }


def notifications(client, headers):
    return result(client.get("/api/v1/notifications/inbox", headers=headers))["items"]


def test_drafts_and_failed_publication_are_private_and_retry_is_atomic(
    client, auth_headers, admin_headers
):
    row = result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=missing(client, auth_headers, source_entity_id=None, missing_source_name="I’ve"),
        )
    )
    initial = user_state(row)
    started = result(action(client, admin_headers, row, "start", public_note="内部调查"))
    assert user_state(user_detail(client, auth_headers, row)) == initial
    draft = result(action(client, admin_headers, started, "draft", public_note="预填发布说明"))
    assert draft["draft"]["source_entity_id"] == ""
    assert draft["review"]["public_note_draft"] == "预填发布说明"
    public = user_detail(client, auth_headers, row)
    assert user_state(public) == initial
    assert public["entity_id"] == ""
    assert notifications(client, auth_headers) == []

    accepted = accept(client, admin_headers, draft)
    accepted_public = user_state(user_detail(client, auth_headers, row))
    assert accepted_public["status_label"] == "已采纳，待发布"
    assert len(notifications(client, auth_headers)) == 1
    failed = action(client, admin_headers, accepted, "publish")
    result(failed, 422)
    current = result(client.get(f"{ADMIN}/{row['id']}", headers=admin_headers))
    assert current["revision"] == accepted["revision"]
    assert current["history"] == accepted["history"]
    assert current["draft"] == draft["draft"]
    assert user_state(user_detail(client, auth_headers, row)) == accepted_public
    assert len(notifications(client, auth_headers)) == 1

    # Fixing the business source requires submitting the changed approval snapshot.
    published = result(
        accept_and_publish(
            client,
            admin_headers,
            accepted,
            changes={
                "source_entity_id": "album-starlit",
                "front_source": {"copyright_status": "AUTHORIZED"},
            },
        )
    )
    assert published["result"] == "INCLUDED"
    public = user_detail(client, auth_headers, row)
    assert public["status_label"] == "已采用" and public["target_available"]
    assert len(public["history"]) == 4
    assert len(notifications(client, auth_headers)) == 3
    with SessionLocal() as db:
        assert db.get(Card, published["entity_id"]).status == "PUBLISHED"


def test_correction_draft_does_not_expose_decisions_or_notify(client, auth_headers, admin_headers):
    row = result(client.post(ROOT, headers=auth_headers, json=correction(client, auth_headers)))
    reviewed = result(
        action(
            client,
            admin_headers,
            row,
            "review",
            decisions=[{"key": "name", "decision": "ACCEPT"}],
            public_note="准备采用，尚未发布",
        )
    )
    assert reviewed["review"]["decisions"]
    current = user_detail(client, auth_headers, row)
    assert user_state(current) == user_state(row)
    assert current["decisions"] == []
    assert notifications(client, auth_headers) == []


def test_wrong_source_rejected_without_losing_revision_then_correct_selection_saves(
    client, auth_headers, admin_headers
):
    with SessionLocal() as db:
        db.add(
            CatalogAlbum(
                id="album-other-group",
                name="Unrelated",
                artist_name="OTHER",
                group_id=None,
                release_date="",
                album_type="EP",
            )
        )
        db.commit()
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    failed = action(
        client,
        admin_headers,
        row,
        "draft",
        changes={"source_entity_id": "album-other-group"},
    )
    result(failed, 422)
    assert "来源不存在" in failed.text
    current = result(client.get(f"{ADMIN}/{row['id']}", headers=admin_headers))
    assert current["revision"] == row["revision"]
    assert current["entity_id"] == ""
    saved = result(
        action(
            client,
            admin_headers,
            row,
            "draft",
            changes={"source_entity_id": "album-starlit"},
        )
    )
    assert saved["draft"]["source_entity_id"] == "album-starlit"


def test_needs_info_resubmission_preserves_record_and_rechecks_new_image(
    client, auth_headers, admin_headers, second_app_headers
):
    body = missing(client, auth_headers)
    row = result(client.post(ROOT, headers=auth_headers, json=body))
    draft = result(
        action(
            client,
            admin_headers,
            row,
            "draft",
            changes={"front_source": {"copyright_status": "AUTHORIZED"}},
        )
    )
    result(action(client, admin_headers, draft, "need_info", public_note="  "), 422)
    requested = result(
        action(
            client,
            admin_headers,
            draft,
            "need_info",
            public_note="请补充清晰正面和正式发行名称",
        )
    )
    public = user_detail(client, auth_headers, row)
    assert public["result"] == "NEEDS_INFO" and public["can_resubmit"]
    assert public["status_label"] == "信息缺失待补充"
    assert len(notifications(client, auth_headers)) == 1
    result(action(client, admin_headers, requested, "publish"), 409)
    image = upload(client, auth_headers)
    resubmission = {
        **body,
        "request_key": str(uuid4()),
        "revision": public["revision"],
        "missing": {**body["missing"], "front_image_id": image["id"]},
        "notes": "已补充清晰图片和来源",
    }
    endpoint = f"{ROOT}/records/{row['id']}/resubmit"
    result(client.post(endpoint, headers=second_app_headers, json=resubmission), 404)
    result(
        client.post(
            endpoint,
            headers=auth_headers,
            json={**resubmission, "revision": public["revision"] - 1},
        ),
        409,
    )
    result(
        client.post(
            endpoint,
            headers=auth_headers,
            json={
                **resubmission,
                "missing": {**resubmission["missing"], "detected_card_id": "other-card"},
            },
        ),
        422,
    )
    submitted = result(client.post(endpoint, headers=auth_headers, json=resubmission))
    assert submitted["id"] == row["id"]
    assert submitted["result"] == "PENDING" and not submitted["can_resubmit"]
    assert submitted["submission"]["front"]["id"] == image["id"]
    assert (
        submitted["submission"]["previous_submissions"][0]["submission"]["front"]
        == row["submission"]["front"]
    )
    assert len(submitted["history"]) == 3
    assert len(notifications(client, auth_headers)) == 1
    replay = result(client.post(endpoint, headers=auth_headers, json=resubmission))
    assert replay["revision"] == submitted["revision"]
    result(
        client.post(
            endpoint,
            headers=auth_headers,
            json={**resubmission, "notes": "same key with changed payload"},
        ),
        409,
    )

    reviewed = result(client.get(f"{ADMIN}/{row['id']}", headers=admin_headers))
    assert reviewed["review"]["submission_changed"]
    saved = result(action(client, admin_headers, reviewed, "draft"))
    assert saved["entity_id"] == draft["entity_id"]  # Reuse the original internal draft.
    assert saved["draft"]["image_url"] == image["image_url"]
    assert saved["draft"]["front_source"]["copyright_status"] == "UNKNOWN"
    assert user_state(user_detail(client, auth_headers, row)) == user_state(submitted)
    included = result(
        accept_and_publish(
            client,
            admin_headers,
            saved,
        )
    )
    assert included["result"] == "INCLUDED"
    assert len(notifications(client, auth_headers)) == 3
    credits = result(client.get(f"{ROOT}/cards/{included['entity_id']}/contributors"))["items"]
    assert len(credits) == 1 and credits[0]["user_id"] == "current-user"
    # A late retry of the original submission still returns this record, not a duplicate.
    initial_retry = result(client.post(ROOT, headers=auth_headers, json=body))
    assert initial_retry["id"] == row["id"] and initial_retry["result"] == "INCLUDED"


def test_rejected_submission_is_retained_and_cannot_be_resubmitted(
    client, auth_headers, admin_headers
):
    body = missing(client, auth_headers)
    row = result(client.post(ROOT, headers=auth_headers, json=body))
    rejected = result(
        action(client, admin_headers, row, "reject", public_note="图片无法证明是正式发行小卡")
    )
    retained = user_detail(client, auth_headers, row)
    assert retained["submission"] == row["submission"]
    assert retained["status_label"] == "无法采用" and not retained["can_resubmit"]
    assert len(retained["history"]) == 2
    assert len(notifications(client, auth_headers)) == 1
    result(
        client.post(
            f"{ROOT}/records/{row['id']}/resubmit",
            headers=auth_headers,
            json={**body, "request_key": str(uuid4()), "revision": rejected["revision"]},
        ),
        409,
    )
    with SessionLocal() as db:
        assert db.get(Feedback, row["id"]) is not None
        assert not db.get(Feedback, row["id"]).entity_id


def test_old_internal_timeline_and_notices_are_hidden_without_deleting_history(
    client, auth_headers, admin_headers
):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    with SessionLocal() as db:
        stored = db.get(Feedback, row["id"])
        stored.status = "PROCESSED"
        stored.public_note = "审核已处理，待正式发布"
        stored.history = [
            *stored.history,
            {
                "at": "2026-10-20T12:00:00+00:00",
                "status": "PROCESSING",
                "result": "PENDING",
                "note": "正在核实",
            },
            {
                "at": "2026-10-20T12:01:00+00:00",
                "status": "PROCESSED",
                "result": "PENDING",
                "note": "审核已处理，待完成发布校验",
            },
        ]
        for suffix, delivered in [("old-delivered", True), ("old-queued", False)]:
            notice_id = f"{row['id']}:{suffix}"
            db.add(
                FeedbackNotice(
                    id=notice_id,
                    user_id="current-user",
                    delivered=delivered,
                    data={
                        "feedback_id": row["id"],
                        "title": "反馈已处理",
                        "body": "审核已处理，待完成发布校验",
                        "status": "PROCESSED",
                        "result": "PENDING",
                    },
                )
            )
            if delivered:
                db.add(
                    NotificationInboxItem(
                        id=notice_id,
                        user_id="current-user",
                        category="CATALOG_FEEDBACK",
                        source_type="feedback",
                        source_id=row["id"],
                        title="反馈已处理",
                        body="审核已处理，待完成发布校验",
                        payload={"feedback_id": row["id"]},
                    )
                )
        db.commit()
    assert user_state(user_detail(client, auth_headers, row)) == user_state(row)
    assert notifications(client, auth_headers) == []
    operator = result(client.get(f"{ADMIN}/{row['id']}", headers=admin_headers))
    assert len(operator["history"]) == 3
    with SessionLocal() as db:
        assert len(db.scalars(select(FeedbackNotice)).all()) == 2
        assert len(db.scalars(select(NotificationInboxItem)).all()) == 1


def test_resubmit_legacy_version_resolves_materialized_version_but_not_archived(
    client, auth_headers, admin_headers
):
    from app.modules.admin.catalog_extensions import CatalogRecord

    options = result(
        client.get(
            "/api/v1/scan/feedback-options",
            headers=auth_headers,
            params={"source": "专辑", "group_id": "group-lumina", "idol_id": "idol-aria"},
        )
    )
    album = next(item for item in options["items"] if item["id"] == "album-starlit")
    legacy = album["versions"][0]
    assert legacy["id"].startswith("legacy_version_")
    body = missing(client, auth_headers, source_version_id=legacy["id"])
    row = result(client.post(ROOT, headers=auth_headers, json=body))
    draft = result(action(client, admin_headers, row, "draft"))
    canonical = draft["draft"]["entity_version_id"]
    assert canonical and not canonical.startswith("legacy_version_")
    requested = result(
        action(client, admin_headers, draft, "need_info", public_note="请补充发行证据")
    )
    resubmission = {
        **body,
        "request_key": str(uuid4()),
        "revision": requested["revision"],
        "missing": {**body["missing"], "front_image_id": row["submission"]["front"]["id"]},
        "notes": "发行说明已补充",
    }
    endpoint = f"{ROOT}/records/{row['id']}/resubmit"
    submitted = result(client.post(endpoint, headers=auth_headers, json=resubmission))
    assert submitted["submission"]["missing"]["source_version_id"] == canonical
    assert submitted["submission"]["missing"]["source_version_name"] == legacy["name"]
    assert (
        submitted["submission"]["previous_submissions"][0]["submission"]["missing"][
            "source_version_id"
        ]
        == legacy["id"]
    )
    reviewed = result(client.get(f"{ADMIN}/{row['id']}", headers=admin_headers))
    again = result(
        action(client, admin_headers, reviewed, "need_info", public_note="请补充背面证据")
    )
    with SessionLocal() as db:
        db.get(CatalogRecord, canonical).status = "ARCHIVED"
        db.commit()
    invalid = client.post(
        endpoint,
        headers=auth_headers,
        json={**resubmission, "request_key": str(uuid4()), "revision": again["revision"]},
    )
    result(invalid, 400)
    assert "版本不存在" in invalid.text
