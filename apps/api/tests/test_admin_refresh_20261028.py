from uuid import uuid4

from test_feedback_workflow import (
    ADMIN,
    ROOT,
    accept_and_publish,
    action,
    correction,
    missing,
    result,
)

from app.modules.admin.import_service import columns


def test_addition_queue_keeps_both_app_submission_types(client, auth_headers, admin_headers):
    card = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    content = result(
        client.post(
            ROOT,
            headers=auth_headers,
            json={
                "kind": "MISSING_CATALOG",
                "request_key": str(uuid4()),
                "entity_type": "groups",
                "fields": [{"key": "name", "value": "New Fixture Group"}],
                "notes": "New group request",
            },
        )
    )
    correction_row = result(
        client.post(ROOT, headers=auth_headers, json=correction(client, auth_headers))
    )
    rows = result(client.get(ADMIN + "?kind=ADDITIONS", headers=admin_headers))["items"]
    assert {r["id"] for r in rows} == {card["id"], content["id"]}
    rows = result(client.get(ADMIN + "?kind=CORRECTION", headers=admin_headers))["items"]
    assert [r["id"] for r in rows] == [correction_row["id"]]


def test_publication_no_longer_requires_operator_provenance_form(
    client, auth_headers, admin_headers
):
    row = result(client.post(ROOT, headers=auth_headers, json=missing(client, auth_headers)))
    saved = result(action(client, admin_headers, row, "draft"))
    assert saved["draft"]["front_source"]["copyright_status"] == "UNKNOWN"
    published = result(accept_and_publish(client, admin_headers, saved))
    assert published["result"] == "INCLUDED"
    # Removing the input does not invent a rights assertion or lose contributor provenance.
    assert published["draft"]["front_source"]["copyright_status"] == "UNKNOWN"
    assert published["draft"]["front_source"]["source_type"] == "USER_SUBMITTED"


def test_business_source_is_still_required(client, auth_headers, admin_headers):
    row = result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=missing(
                client, auth_headers, source_entity_id=None, missing_source_name="Unknown"
            ),
        )
    )
    draft = result(action(client, admin_headers, row, "draft"))
    response = accept_and_publish(client, admin_headers, draft)
    assert response.status_code == 422
    assert "至少关联" in response.text


def test_retired_queue_routes_are_removed(client, admin_headers):
    for path in ("/review-queue", "/quality"):
        assert client.get("/api/v1/admin/console" + path, headers=admin_headers).status_code == 404


def test_import_templates_do_not_ask_for_provenance():
    for kind in ("cards", "groups", "idols", "albums", "events", "others", "groups_idols"):
        assert not any(
            "copyright" in key or key.endswith(("source_type", "source_url"))
            for key in columns(kind)
        )
    assert "source_entity_id" in columns("cards")


def test_legacy_scan_feedback_write_is_retired(client, auth_headers):
    assert client.post("/api/v1/scan/feedback", headers=auth_headers).status_code in {404, 405}


def test_hidden_social_provenance_is_preserved_on_edit(client, admin_headers):
    row = result(
        client.post(
            "/api/v1/admin/console/operations/social",
            headers=admin_headers,
            json={
                "group_id": "group-lumina",
                "title": "Old content",
                "content": "Old content",
                "source_url": "https://example.com/original",
            },
        )
    )
    saved = result(
        client.put(
            "/api/v1/admin/console/operations/social/" + row["id"],
            headers=admin_headers,
            json={
                "group_id": "group-lumina",
                "title": "Updated content",
                "content": "Updated content",
            },
        )
    )
    assert saved["original_url"] == "https://example.com/original"


def test_generic_record_routes_cannot_recreate_retired_queue(client, admin_headers):
    base = "/api/v1/admin/console/records/reviews"
    assert client.get(base, headers=admin_headers).status_code == 404
    assert (
        client.post(
            base,
            headers=admin_headers,
            json={"entity_type": "cards", "status": "PENDING", "data": {"name": "Retired"}},
        ).status_code
        == 422
    )


def test_album_management_permission_reaches_reads_and_entitlements(
    client, admin_headers, admin_actor_headers
):
    actor = admin_actor_headers("content_operator", "album-manager-only")
    matrix = result(client.get("/api/v1/admin/console/roles", headers=admin_headers))
    result(
        client.put(
            "/api/v1/admin/console/roles",
            headers=admin_headers,
            json={
                "version": matrix["version"],
                "roles": {**matrix["roles"], "content_operator": ["albums.manage"]},
            },
        )
    )
    for path in ("/album-settings", "/album-materials/SHELF", "/digital-albums"):
        result(client.get("/api/v1/admin/console" + path, headers=actor))
    result(
        client.put(
            "/api/v1/admin/console/album-entitlements/current-user",
            headers=actor,
            json={"plan": "PRO"},
        )
    )
    assert (
        client.put(
            "/api/v1/admin/console/digital-albums/not-found/moderation",
            headers=actor,
            json={"status": "OFFLINE", "reason": "No review permission"},
        ).status_code
        == 403
    )


def test_permission_dependencies_reject_unreachable_management_config(client, admin_headers):
    matrix = result(client.get("/api/v1/admin/console/roles", headers=admin_headers))
    url = "/api/v1/admin/console/roles"
    for key in (
        "auth.users.manage",
        "auth.users.sensitive",
        "auth.identities.unbind",
        "auth.test_code.manage",
    ):
        response = client.put(
            url,
            headers=admin_headers,
            json={
                "version": matrix["version"],
                "roles": {**matrix["roles"], "content_operator": [key]},
            },
        )
        assert response.status_code == 422
    result(
        client.put(
            url,
            headers=admin_headers,
            json={
                "version": matrix["version"],
                "roles": {
                    **matrix["roles"],
                    "content_operator": ["auth.users.view", "auth.users.manage"],
                },
            },
        )
    )
