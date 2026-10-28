import pytest
from sqlalchemy import select

from app.admin_models import ContentMetadata
from app.core.database import SessionLocal
from app.models import OperationLog

ROOT = "/api/v1/admin/console"


def create_group(client, headers, name):
    response = client.post(ROOT + "/entities/groups", headers=headers, json={"name": name})
    assert response.status_code == 200, response.text
    return response.json()["data"]["id"]


def archive(client, headers, kind, item_id):
    response = client.post(
        ROOT + f"/entities/{kind}/{item_id}/actions", headers=headers, json={"action": "archive"}
    )
    assert response.status_code == 200, response.text


def test_delete_requires_archive_and_retains_audit(client, admin_headers):
    item_id = create_group(client, admin_headers, "Unlinked")
    url = ROOT + f"/entities/groups/{item_id}"
    assert (
        client.post(
            ROOT + f"/entities/groups/{item_id}/actions",
            headers=admin_headers,
            json={"action": "submit"},
        ).status_code
        == 200
    )
    assert client.delete(url, headers=admin_headers).status_code == 409
    assert (
        client.post(
            ROOT + f"/entities/groups/{item_id}/actions",
            headers=admin_headers,
            json={"action": "reject", "reason": "test"},
        ).status_code
        == 200
    )
    archive(client, admin_headers, "groups", item_id)
    assert client.delete(url, headers=admin_headers).status_code == 200
    assert client.delete(url, headers=admin_headers).status_code == 404
    with SessionLocal() as db:
        assert (
            db.scalar(select(ContentMetadata).where(ContentMetadata.entity_id == item_id)) is None
        )
        assert (
            db.scalar(select(OperationLog).where(OperationLog.action == "catalog.entity.delete"))
            is not None
        )


@pytest.mark.parametrize("kind", ["idols", "albums", "events"])
def test_upstream_group_blocks_delete(client, admin_headers, kind):
    response = client.post(
        ROOT + f"/entities/{kind}",
        headers=admin_headers,
        json={
            "name": "Linked",
            "group_id": "group-lumina",
            **({"city": "Seoul"} if kind == "events" else {}),
        },
    )
    assert response.status_code == 200, response.text
    item_id = response.json()["data"]["id"]
    archive(client, admin_headers, kind, item_id)
    response = client.delete(ROOT + f"/entities/{kind}/{item_id}", headers=admin_headers)
    assert response.status_code == 409
    assert "组合" in response.text


def test_batch_delete_rolls_back_when_json_key_references_record(client, admin_headers):
    first = create_group(client, admin_headers, "First")
    second = create_group(client, admin_headers, "Second")
    for item_id in [first, second]:
        archive(client, admin_headers, "groups", item_id)
    with SessionLocal() as db:
        db.add(
            ContentMetadata(
                entity_type="daily",
                entity_id="pool",
                status="DRAFT",
                operator_id="user-admin",
                data={"weights": {second: 2}},
            )
        )
        db.commit()
    response = client.post(
        ROOT + "/entities/groups/batch",
        headers=admin_headers,
        json={"ids": [first, second], "action": "delete"},
    )
    assert response.status_code == 409, response.text
    with SessionLocal() as db:
        assert (
            db.scalar(select(ContentMetadata).where(ContentMetadata.entity_id == first)) is not None
        )
        assert (
            db.scalar(select(OperationLog).where(OperationLog.action == "catalog.entity.delete"))
            is None
        )


def test_archived_downstream_blocks_group_delete(client, admin_headers):
    group = create_group(client, admin_headers, "Parent")
    child = client.post(
        ROOT + "/entities/albums", headers=admin_headers, json={"name": "Child", "group_id": group}
    ).json()["data"]["id"]
    archive(client, admin_headers, "albums", child)
    archive(client, admin_headers, "groups", group)
    response = client.delete(ROOT + f"/entities/groups/{group}", headers=admin_headers)
    assert response.status_code == 409
    assert "专辑" in response.text


def test_card_upstream_blocks_single_and_batch_delete(client, admin_headers):
    for action in ["offline", "archive"]:
        response = client.post(
            ROOT + "/cards/card-aria-01/actions", headers=admin_headers, json={"action": action}
        )
        assert response.status_code == 200, response.text
    response = client.delete(ROOT + "/cards/card-aria-01", headers=admin_headers)
    assert response.status_code == 409
    assert "所属组合" in response.text
    response = client.post(
        ROOT + "/cards/batch",
        headers=admin_headers,
        json={"ids": ["card-aria-01"], "action": "delete"},
    )
    assert response.status_code == 409


def test_regular_user_cannot_delete(client, admin_headers, auth_headers):
    item_id = create_group(client, admin_headers, "Protected")
    archive(client, admin_headers, "groups", item_id)
    assert (
        client.delete(ROOT + f"/entities/groups/{item_id}", headers=auth_headers).status_code == 401
    )
