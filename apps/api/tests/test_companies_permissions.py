from test_catalog_bulk import confirm, preview

from app.core.database import SessionLocal
from app.modules.admin.catalog_extensions import CatalogRecord

ROOT = "/api/v1/admin/console"


def data(response, status=200):
    assert response.status_code == status, response.text
    return response.json().get("data")


def company(client, headers, name="New Company", enabled=True):
    return data(
        client.post(
            ROOT + "/records/companies",
            headers=headers,
            json={"data": {"name": name, "enabled": enabled}},
        )
    )


def test_roles_enforced_immediately_with_no_privilege_escalation(
    client, admin_headers, admin_actor_headers
):
    operator = admin_actor_headers("content_operator", "content-permissions")
    before = data(client.get(ROOT + "/roles", headers=admin_headers))
    data(client.get(ROOT + "/roles", headers=operator), 403)
    assert "catalog.edit" in data(client.get(ROOT + "/me", headers=operator))["permissions"]
    roles = {**before["roles"], "content_operator": ["catalog.view"]}
    updated = data(
        client.put(
            ROOT + "/roles",
            headers=admin_headers,
            json={"version": before["version"], "roles": roles},
        )
    )
    assert updated["version"] == before["version"] + 1
    data(
        client.post(
            ROOT + "/records/companies", headers=operator, json={"data": {"name": "Forbidden"}}
        ),
        403,
    )
    assert data(client.get(ROOT + "/me", headers=operator))["permissions"] == ["catalog.view"]
    data(
        client.put(
            ROOT + "/roles",
            headers=admin_headers,
            json={"version": before["version"], "roles": roles},
        ),
        409,
    )
    for bad in [
        {"admin": []},
        {"content_operator": ["catalog.view", "auth.admins.manage"]},
        {"content_operator": ["invented"]},
        {"content_operator": ["catalog.edit"]},
    ]:
        data(
            client.put(
                ROOT + "/roles",
                headers=admin_headers,
                json={"version": updated["version"], "roles": {**roles, **bad}},
            ),
            422,
        )
    roles["content_operator"] = ["catalog.view", "catalog.edit", "auth.users.view"]
    restored = data(
        client.put(
            ROOT + "/roles",
            headers=admin_headers,
            json={"version": updated["version"], "roles": roles},
        )
    )
    assert restored["version"] == updated["version"] + 1
    company(client, operator)
    data(client.get("/api/v1/admin/auth/users", headers=operator))
    data(
        client.put(
            ROOT + "/roles", headers=operator, json={"version": restored["version"], "roles": roles}
        ),
        403,
    )


def test_disabled_company_blocks_new_selection_but_preserves_history(client, admin_headers):
    c = company(client, admin_headers)
    group = data(
        client.post(
            ROOT + "/entities/groups",
            headers=admin_headers,
            json={"name": "Toggle Group", "company_ids": [c["id"]]},
        )
    )
    c = data(
        client.put(
            ROOT + "/records/companies/" + c["id"],
            headers=admin_headers,
            json={"data": {**c["data"], "enabled": False}},
        )
    )
    assert c["data"]["enabled"] is False
    data(
        client.post(
            ROOT + "/entities/groups",
            headers=admin_headers,
            json={"name": "Other Group", "company_ids": [c["id"]]},
        ),
        422,
    )
    saved = data(
        client.put(
            ROOT + "/entities/groups/" + group["id"],
            headers=admin_headers,
            json={"name": "Toggle Group Edited", "company_ids": [c["id"]]},
        )
    )
    assert saved["company_ids"] == [c["id"]]
    # New dated relations must use an enabled company, even via low-level API.
    data(
        client.post(
            ROOT + "/records/company_relations",
            headers=admin_headers,
            json={
                "entity_type": "groups",
                "entity_id": "group-lumina",
                "data": {"company_id": c["id"], "start_date": "2026-01-01"},
            },
        ),
        422,
    )
    detail = data(
        client.get(ROOT + "/records/companies/" + c["id"] + "/detail", headers=admin_headers)
    )
    assert any(row["entity_id"] == group["id"] for row in detail["groups"])
    data(
        client.put(
            ROOT + "/records/companies/" + c["id"],
            headers=admin_headers,
            json={"data": {**c["data"], "enabled": True}},
        )
    )
    company_id = data(
        client.post(
            ROOT + "/entities/groups",
            headers=admin_headers,
            json={"name": "Now Allowed", "company_ids": [c["id"]]},
        )
    )["company_ids"][0]
    assert company_id == c["id"]


def test_company_imports_are_enabled_and_unknown_company_auto_created(client, admin_headers):
    task = preview(
        client, admin_headers, "companies", [{"name": "Import Co", "description": "company import"}]
    )
    data(confirm(client, admin_headers, task))
    task = preview(
        client, admin_headers, "groups", [{"name": "Import Group", "company": "New Auto Company"}]
    )
    result = data(confirm(client, admin_headers, task))
    group_id = result["rows"][0]["created_id"]
    group = data(
        client.get(ROOT + "/entities/groups/" + group_id + "/detail", headers=admin_headers)
    )["entity"]
    assert len(group["company_ids"]) == 1
    with SessionLocal() as db:
        record = db.get(CatalogRecord, group["company_ids"][0])
        assert record.data["name"] == "New Auto Company"
        assert record.data["enabled"] is True
    rows = data(client.get(ROOT + "/records/companies", headers=admin_headers))["items"]
    assert (
        next(row for row in rows if row["data"]["name"] == "Import Co")["data"]["enabled"] is True
    )


def test_company_legacy_default_and_explicit_state(client, admin_headers):
    with SessionLocal() as db:
        for name, status in [("Legacy Draft", "DRAFT"), ("Legacy Archived", "ARCHIVED")]:
            db.add(CatalogRecord(id=name, kind="companies", status=status, data={"name": name}))
        db.commit()
    rows = data(client.get(ROOT + "/records/companies", headers=admin_headers))["items"]
    assert next(row for row in rows if row["id"] == "Legacy Draft")["data"]["enabled"] is True
    assert next(row for row in rows if row["id"] == "Legacy Archived")["data"]["enabled"] is False
    enabled = data(
        client.put(
            ROOT + "/records/companies/Legacy Archived",
            headers=admin_headers,
            json={"data": {"name": "Legacy Archived", "enabled": True}},
        )
    )
    assert enabled["status"] == "ARCHIVED" and enabled["data"]["enabled"] is True
    data(
        client.post(
            ROOT + "/records/companies",
            headers=admin_headers,
            json={"data": {"name": "Wrong Bool", "enabled": "false"}},
        ),
        422,
    )


def test_catalog_read_revocation_and_independent_publish_delete(
    client, admin_headers, admin_actor_headers
):
    operator = admin_actor_headers("content_operator", "review-only")
    matrix = data(client.get(ROOT + "/roles", headers=admin_headers))
    roles = {**matrix["roles"], "content_operator": []}
    matrix = data(
        client.put(
            ROOT + "/roles",
            headers=admin_headers,
            json={"version": matrix["version"], "roles": roles},
        )
    )
    for path in [
        "/catalog",
        "/catalog-dashboard",
        "/scan-index",
        "/records/companies",
        "/entities/idols/idol-aria/detail",
        "/profiles/idols/idol-aria",
        "/tags",
    ]:
        data(client.get(ROOT + path, headers=operator), 403)
    roles["content_operator"] = ["catalog.view", "catalog.publish", "catalog.delete"]
    data(
        client.put(
            ROOT + "/roles",
            headers=admin_headers,
            json={"version": matrix["version"], "roles": roles},
        )
    )
    group = data(
        client.post(ROOT + "/entities/groups", headers=admin_headers, json={"name": "Review only"})
    )
    data(
        client.post(
            ROOT + "/entities/groups/" + group["id"] + "/actions",
            headers=admin_headers,
            json={"action": "submit"},
        )
    )
    result = data(
        client.post(
            ROOT + "/entities/groups/" + group["id"] + "/actions",
            headers=operator,
            json={"action": "publish"},
        )
    )
    assert result["status"] == "PUBLISHED"
    data(
        client.put(
            ROOT + "/entities/groups/" + group["id"], headers=operator, json={"name": "Blocked"}
        ),
        403,
    )
    data(client.get(ROOT + "/profiles/groups/" + group["id"], headers=operator))
    draft = data(
        client.post(ROOT + "/entities/groups", headers=admin_headers, json={"name": "Delete only"})
    )
    data(client.delete(ROOT + "/entities/groups/" + draft["id"], headers=operator))


def test_disabled_company_import_is_not_reenabled_or_duplicated(client, admin_headers):
    c = company(client, admin_headers, "Disabled Import Co", False)
    for kind, row in [
        ("groups", {"name": "Blocked Group", "company": "Disabled Import Co"}),
        (
            "groups_idols",
            {
                "group_code": "disabled",
                "group_name": "Blocked Group",
                "group_company": "Disabled Import Co",
                "idol_name": "Member",
            },
        ),
    ]:
        task = preview(client, admin_headers, kind, [row])
        assert task["errors"] and "未开启" in task["errors"][0]["message"]
        data(confirm(client, admin_headers, task), 422)
    with SessionLocal() as db:
        assert db.get(CatalogRecord, c["id"]).data["enabled"] is False


def test_profile_company_new_and_disabled_history(client, admin_headers):
    from uuid import uuid4

    c = company(client, admin_headers, "Profile New Agency")
    path = ROOT + "/profiles/idols/idol-aria"

    def publish(operations, status=200):
        current = data(client.get(path, headers=admin_headers))
        return data(
            client.post(
                path + "/publish",
                headers=admin_headers,
                json={
                    "expected": current["version"],
                    "draft_version": current["draft_version"],
                    "request_key": str(uuid4()),
                    "summary": "核实经纪公司经历",
                    "values": {"company_relations": operations},
                },
            ),
            status,
        )

    published = publish(
        [{"operation": "ADD", "data": {"target_id": c["id"], "start_date": "2020-01-01"}}]
    )
    relation = published["snapshot"]["company_relations"][0]
    data(
        client.put(
            ROOT + "/records/companies/" + c["id"],
            headers=admin_headers,
            json={"data": {**c["data"], "enabled": False}},
        )
    )
    publish([{"operation": "ADD", "data": {"target_id": c["id"], "start_date": "2026-01-01"}}], 422)
    edited = publish(
        [
            {
                "operation": "UPDATE",
                "id": relation["id"],
                "data": {
                    "target_id": c["id"],
                    "start_date": "2020-01-01",
                    "end_date": "2025-01-01",
                },
            }
        ]
    )
    assert edited["snapshot"]["company_relations"][0]["end_date"] == "2025-01-01"
