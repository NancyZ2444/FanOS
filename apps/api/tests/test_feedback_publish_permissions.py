"""Publish-only review permissions never grant ordinary draft editing."""

from uuid import uuid4

import pytest
from test_feedback_workflow import (
    ADMIN,
    ROOT,
    accept,
    accept_and_publish,
    action,
    missing,
    result,
    upload,
)
from test_missing_catalog_feedback import body as missing_catalog_body

from app.auth_models import AdminPrincipal, AuthState
from app.common.response import DomainError
from app.core.database import SessionLocal
from app.models import Card
from app.modules.admin import catalog_service as catalog
from app.modules.admin.console_schemas import CardDraft, EntityDraft
from app.modules.feedback.models import Feedback
from app.modules.feedback.service import feedback_publication

CONSOLE = "/api/v1/admin/console"
PUBLISHER_ID = "feedback-publisher-only"


@pytest.fixture
def publisher(client, admin_headers, admin_actor_headers):
    headers = admin_actor_headers("content_operator", PUBLISHER_ID)
    roles = result(client.get(CONSOLE + "/roles", headers=admin_headers))
    result(
        client.put(
            CONSOLE + "/roles",
            headers=admin_headers,
            json={
                "version": roles["version"],
                "roles": {
                    **roles["roles"],
                    "content_operator": ["catalog.view", "catalog.publish"],
                },
            },
        )
    )
    return headers


def test_publish_missing_card_without_edit_and_no_direct_drafts(
    client, auth_headers, publisher, admin_headers
):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    result(action(client, publisher, row, "draft"), 403)
    result(client.post(CONSOLE + "/cards", headers=publisher, json={"title": "Forbidden"}), 403)
    # Invalid publication rolls back its nested writes and does not leave an editing grant.
    accepted = accept(client, publisher, row, changes={"group_id": "missing-group"})
    result(action(client, publisher, accepted, "publish"), 422)
    after = result(client.get(ADMIN + "/" + row["id"], headers=publisher))
    assert not after["entity_id"] and after["result"] == "PENDING"
    assert after["review_decision"] == "ACCEPTED" and after["revision"] == accepted["revision"]
    result(client.post(CONSOLE + "/cards", headers=publisher, json={"title": "Forbidden"}), 403)
    published = result(accept_and_publish(client, publisher, after))
    assert published["result"] == "INCLUDED" and published["target_available"]
    draft = result(
        client.post(
            CONSOLE + "/cards",
            headers=admin_headers,
            json={
                "title": "Draft",
                "group_id": "group-lumina",
                "idol_id": "idol-aria",
                "source_entity_type": "ALBUM",
                "source_entity_id": "album-starlit",
            },
        )
    )
    result(
        client.put(CONSOLE + "/cards/" + draft["id"], headers=publisher, json={"title": "No"}), 403
    )
    result(
        client.post(
            CONSOLE + "/cards/" + draft["id"] + "/actions",
            headers=publisher,
            json={"action": "submit"},
        ),
        403,
    )


@pytest.mark.parametrize(
    "kind,extra",
    [
        ("groups", {}),
        ("idols", {}),
        ("albums", {"artists": [{"type": "groups", "id": "group-lumina"}], "versions": ["First"]}),
        (
            "events",
            {
                "artists": [{"type": "groups", "id": "group-lumina"}],
                "is_online": True,
                "platform": "Official",
            },
        ),
        ("others", {"artists": [{"type": "idols", "id": "idol-aria"}]}),
        ("versions", {"album_id": "album-starlit"}),
    ],
)
def test_publish_missing_entity_without_edit(client, auth_headers, publisher, kind, extra):
    asset = upload(client, auth_headers)
    row = result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=missing_catalog_body(
                kind, name="Reviewed " + kind, image_url=asset["id"], **extra
            ),
        )
    )
    result(action(client, publisher, row, "draft"), 403)
    published = result(accept_and_publish(client, publisher, row))
    assert published["result"] == "INCLUDED" and published["target_available"]
    if kind != "versions":
        result(
            client.post(CONSOLE + "/entities/" + kind, headers=publisher, json={"name": "Direct"}),
            403,
        )


@pytest.mark.parametrize(
    "kind,item_id,field",
    [("albums", "album-starlit", "name"), ("cards", "card-aria-01", "image_url")],
)
def test_publish_correction_without_edit(client, auth_headers, publisher, kind, item_id, field):
    with SessionLocal() as db:
        card = db.get(Card, "card-aria-01")
        card.admin_data = {
            **card.admin_data,
            "source_entity_type": "ALBUM",
            "source_entity_id": "album-starlit",
        }
        db.commit()
    obj = result(client.get(ROOT + f"/objects/{kind}/{item_id}", headers=auth_headers))
    value = upload(client, auth_headers)["id"] if field == "image_url" else "Reviewed title"
    row = result(
        client.post(
            ROOT,
            headers=auth_headers,
            json={
                "kind": "CORRECTION",
                "entity_type": kind,
                "entity_id": item_id,
                "object_version": obj["version"],
                "request_key": str(uuid4()),
                "fields": [{"key": field, "value": value}],
            },
        )
    )
    result(
        action(client, publisher, row, "review", decisions=[{"key": field, "decision": "ACCEPT"}]),
        403,
    )
    published = result(
        accept_and_publish(
            client,
            publisher,
            row,
            object_version=obj["version"],
            decisions=[{"key": field, "decision": "ACCEPT"}],
        )
    )
    assert published["result"] == "INCLUDED" and published["target_available"]


def test_publication_context_cannot_edit_unrelated_objects_or_outlive_review(
    client, auth_headers, publisher
):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    with SessionLocal() as db:
        actor = db.get(AdminPrincipal, PUBLISHER_ID)
        feedback = db.get(Feedback, row["id"])
        feedback.handler_id = actor.id
        with feedback_publication(db, feedback.id):
            # Same transaction does not permit writes to another type or another existing object.
            for operation in [
                lambda: catalog.save_entity(
                    db, actor, "groups", EntityDraft(name="No"), submission_id=feedback.id
                ),
                lambda: catalog.save_card(
                    db, actor, CardDraft(title="No"), "card-aria-01", submission_id=feedback.id
                ),
                lambda: catalog.save_card(
                    db, actor, CardDraft(title="No"), submission_id="wrong-feedback"
                ),
            ]:
                with pytest.raises(DomainError) as error:
                    operation()
                assert error.value.error_code == "PERMISSION_DENIED"
            feedback.handler_id = "another-handler"
            with pytest.raises(DomainError):
                catalog.save_card(db, actor, CardDraft(title="No"), submission_id=feedback.id)
        assert not db.info.get("active_feedback_publication")
        feedback.handler_id = actor.id
        with pytest.raises(RuntimeError), feedback_publication(db, feedback.id):
            raise RuntimeError("publication failed")
        assert not db.info.get("active_feedback_publication")
        permissions = db.get(AuthState, "admin-role-permissions")
        permissions.data = {**permissions.data, "content_operator": ["catalog.view"]}
        db.flush()
        with feedback_publication(db, feedback.id), pytest.raises(DomainError):
            catalog.save_card(db, actor, CardDraft(title="No"), submission_id=feedback.id)
        with pytest.raises(DomainError):
            catalog.save_card(db, actor, CardDraft(title="No"), submission_id=feedback.id)
