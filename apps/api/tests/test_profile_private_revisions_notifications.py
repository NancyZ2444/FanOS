from uuid import uuid4

from test_feedback_workflow import result

from app.core.database import SessionLocal
from app.future_models import NotificationInboxItem
from app.modules.admin.catalog_extensions import CatalogRecord

PUBLIC = "/api/v1/catalog/profiles/idols/idol-aria"
ADMIN = "/api/v1/admin/console/profiles/idols/idol-aria"


def test_internal_publish_needs_no_public_summary_and_archive_is_private(
    client, admin_headers, auth_headers
):
    obj = result(client.get(ADMIN, headers=admin_headers))
    body = {
        "expected": obj["version"],
        "request_key": str(uuid4()),
        "values": {"honors_text": "New honors"},
    }
    draft = result(client.put(ADMIN + "/draft", headers=admin_headers, json=body))
    body["draft_version"] = draft["draft_version"]
    published = result(client.post(ADMIN + "/publish", headers=admin_headers, json=body))
    assert (
        next(f for f in result(client.get(PUBLIC))["fields"] if f["key"] == "honors_text")[
            "current"
        ]
        == "New honors"
    )
    assert result(client.get(PUBLIC + "/history"))["items"] == []
    result(client.get(PUBLIC + "/history/" + published["id"]), 404)
    archive = result(client.get(ADMIN + "/history", headers=admin_headers))["items"]
    assert len(archive) == 2 and archive[0]["visibility"] == "INTERNAL"
    result(client.get(ADMIN + "/history", headers=auth_headers), 401)
    with SessionLocal() as db:
        version = db.get(CatalogRecord, published["id"])
        version.data = {**version.data, "summary": "Private operational note"}
        version.data = {k: v for k, v in version.data.items() if k != "visibility"}
        db.commit()
    assert result(client.get(PUBLIC + "/history"))["items"] == []
    result(client.get(PUBLIC + "/history/" + published["id"]), 404)
    assert (
        result(client.get(ADMIN + "/history/" + published["id"], headers=admin_headers))["summary"]
        == "Private operational note"
    )


def test_notice_categories_filter_before_limit_and_keep_read_action(client, auth_headers):
    with SessionLocal() as db:
        for i in range(105):
            db.add(
                NotificationInboxItem(
                    id=f"feedback-{i}",
                    user_id="current-user",
                    category="CATALOG_FEEDBACK",
                    source_type="feedback",
                    source_id=str(i),
                    title="反馈",
                    body="公开结果",
                    payload={"feedback_id": str(i)},
                )
            )
        db.add(
            NotificationInboxItem(
                id="notice",
                user_id="current-user",
                category="OPERATION",
                source_type="notification",
                source_id="notice",
                title="运营通知",
                body="内容",
                payload={},
            )
        )
        db.add(
            NotificationInboxItem(
                id="legacy-feedback",
                user_id="current-user",
                category="GENERAL",
                source_type="feedback",
                source_id="legacy",
                title="历史反馈",
                body="内容",
                payload={"feedback_id": "legacy"},
            )
        )
        db.add(
            NotificationInboxItem(
                id="other-user-notice",
                user_id="other",
                category="OPERATION",
                source_type="notification",
                source_id="other",
                title="他人消息",
                body="不可见",
                payload={},
            )
        )
        db.commit()
    notices = result(
        client.get("/api/v1/notifications/inbox?category=NOTIFICATION", headers=auth_headers)
    )["items"]
    assert [x["id"] for x in notices] == ["notice"]
    feedback = result(
        client.get("/api/v1/notifications/inbox?category=FEEDBACK_RESULT", headers=auth_headers)
    )["items"]
    assert len(feedback) == 100 and all(x["payload"].get("feedback_id") for x in feedback)
    result(client.post("/api/v1/notifications/inbox/notice/read", headers=auth_headers))
    assert result(
        client.get("/api/v1/notifications/inbox?category=NOTIFICATION", headers=auth_headers)
    )["items"][0]["read_at"]
