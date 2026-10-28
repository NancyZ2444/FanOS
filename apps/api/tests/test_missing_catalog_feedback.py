from uuid import uuid4

import pytest
from sqlalchemy import select
from test_feedback_workflow import ADMIN, ROOT, accept, accept_and_publish, action, result, upload

from app.core.database import SessionLocal
from app.modules.admin.catalog_extensions import CatalogRecord
from app.modules.feedback.models import Feedback


def body(kind, **values):
    return {
        "kind": "MISSING_CATALOG",
        "entity_type": kind,
        "request_key": str(uuid4()),
        "fields": [{"key": key, "value": value} for key, value in values.items()],
    }


@pytest.mark.parametrize(
    "kind,extra",
    [
        ("groups", {"name_translated": "测试组合", "release_date": "2020-01-01"}),
        ("idols", {"real_name": "测试艺人", "release_date": "2000-01-01"}),
        ("albums", {"artists": [{"type": "groups", "id": "group-lumina"}], "versions": ["First"]}),
        (
            "events",
            {
                "artists": [{"type": "groups", "id": "group-lumina"}],
                "is_online": True,
                "platform": "Official",
            },
        ),
        ("others", {"artists": [{"type": "idols", "id": "idol-aria"}], "start_date": "2020-01-01"}),
        ("versions", {"album_id": "album-starlit"}),
    ],
)
def test_six_types_draft_publish_is_reviewed_and_idempotent(
    client, auth_headers, admin_headers, kind, extra
):
    schema = result(
        client.get(
            ROOT + "/missing-catalog/schema", headers=auth_headers, params={"entity_type": kind}
        )
    )
    assert schema["entity_type"] == kind
    keys = {f["key"] for f in schema["fields"]}
    assert "name" in keys and not keys & {"status", "code", "card_count", "member_count"}
    image = upload(client, auth_headers)
    submission = body(kind, name="New " + kind, image_url=image["id"], **extra)
    row = result(client.post(ROOT, headers=auth_headers, json=submission))
    assert row["result"] == "PENDING" and not row["entity_id"]
    assert result(client.post(ROOT, headers=auth_headers, json=submission))["id"] == row["id"]
    draft = result(action(client, admin_headers, row, "draft"))
    assert draft["result"] == "PENDING" and not draft["entity_id"]
    with SessionLocal() as db:
        assert db.get(Feedback, row["id"]).review["catalog_draft"]["name"] == "New " + kind
        if kind == "versions":
            assert not db.scalar(
                select(CatalogRecord).where(
                    CatalogRecord.kind == "versions",
                    CatalogRecord.data["name"].as_string() == "New versions",
                )
            )
    published = result(accept_and_publish(client, admin_headers, draft))
    assert published["result"] == "INCLUDED" and published["status"] == "PROCESSED"
    assert published["target_available"] and published["entity_type"] == kind
    assert (
        "name" in published["review"]["adopted_fields"]
        and "image_url" in published["review"]["adopted_fields"]
    )
    actual = result(
        client.get(ROOT + f"/objects/{kind}/{published['entity_id']}", headers=auth_headers)
    )
    assert actual["image_url"] == image["image_url"]
    mine = result(client.get(ROOT, headers=auth_headers, params={"kind": "MISSING_CATALOG"}))
    assert row["id"] in {item["id"] for item in mine["items"]}
    result(action(client, admin_headers, published, "publish"), 409)


def test_schema_images_objective_fields_and_permissions(
    client, auth_headers, second_app_headers, admin_headers
):
    for kind in ["cards", "companies", "status"]:
        result(
            client.get(
                ROOT + "/missing-catalog/schema", headers=auth_headers, params={"entity_type": kind}
            ),
            422,
        )
    result(
        client.post(ROOT, headers=auth_headers, json=body("groups", name="No", status="PUBLISHED")),
        422,
    )
    image = upload(client, second_app_headers)
    result(
        client.post(
            ROOT, headers=auth_headers, json=body("groups", name="No", image_url=image["id"])
        ),
        422,
    )
    result(client.post(ROOT, headers=auth_headers, json=body("versions", name="No")), 422)
    result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=body("groups", name="No", image_url="https://example.com/image.jpg"),
        ),
        422,
    )
    row = result(client.post(ROOT, headers=auth_headers, json=body("groups", name="Review only")))
    result(action(client, auth_headers, row, "publish"), 401)
    result(client.get(ROOT + "/records/" + row["id"], headers=second_app_headers), 404)
    rejected = result(action(client, admin_headers, row, "reject"))
    assert rejected["result"] == "NOT_INCLUDED" and not rejected["entity_id"]


def test_version_duplicate_rolls_back_and_draft_clear_stays_cleared(
    client, auth_headers, admin_headers
):
    row = result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=body(
                "versions", name="New version", album_id="album-starlit", description="remove me"
            ),
        )
    )
    draft = result(action(client, admin_headers, row, "draft", changes={"description": ""}))
    published = result(accept_and_publish(client, admin_headers, draft))
    assert "description" not in published["review"]["adopted_fields"]
    row2 = result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=body("versions", name="New version", album_id="album-starlit"),
        )
    )
    accepted = accept(client, admin_headers, row2)
    result(action(client, admin_headers, accepted, "publish"), 409)
    unchanged = result(client.get(ADMIN + "/" + row2["id"], headers=admin_headers))
    assert unchanged["result"] == "PENDING" and not unchanged["entity_id"]
    assert unchanged["review_decision"] == "ACCEPTED"
    assert unchanged["revision"] == accepted["revision"]


def test_operator_may_draft_but_not_publish_and_no_public_draft(
    client, auth_headers, admin_actor_headers
):
    operator = admin_actor_headers("content_operator", "catalog-missing-reviewer")
    row = result(
        client.post(ROOT, headers=auth_headers, json=body("groups", name="Hidden review draft"))
    )
    draft = result(action(client, operator, row, "draft"))
    result(action(client, operator, draft, "publish"), 403)
    public = result(
        client.get(
            ROOT + "/objects",
            headers=auth_headers,
            params={"entity_type": "groups", "q": "Hidden review draft"},
        )
    )
    assert public["items"] == []
    assert not draft["entity_id"]


def test_missing_version_retains_owned_scan_context(client, auth_headers, second_app_headers):
    from test_feedback_workflow import missing

    scan = missing(client, auth_headers)["missing"]
    context = {key: scan[key] for key in ["scan_session_id", "detected_card_id"]}
    request = {**body("versions", name="Signed", album_id="album-starlit"), "missing": context}
    row = result(client.post(ROOT, headers=auth_headers, json=request))
    assert row["submission"]["scan"]["detected_card_id"] == context["detected_card_id"]
    assert row["submission"]["scan"]["crop_image_url"]
    result(
        client.post(
            ROOT, headers=second_app_headers, json={**request, "request_key": str(uuid4())}
        ),
        404,
    )


@pytest.mark.parametrize(
    "kind,key,maximum",
    [("groups", "region", 80), ("albums", "type", 80), ("events", "platform", 120)],
)
def test_submission_limits_match_formal_catalog_model(client, auth_headers, kind, key, maximum):
    schema = result(
        client.get(
            ROOT + "/missing-catalog/schema", headers=auth_headers, params={"entity_type": kind}
        )
    )
    assert next(field for field in schema["fields"] if field["key"] == key)["max_length"] == maximum
    result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=body(kind, name="Length boundary", **{key: "a" * maximum}),
        )
    )
    result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=body(kind, name="Overlong", **{key: "a" * (maximum + 1)}),
        ),
        422,
    )


@pytest.mark.parametrize("invalid", [{"url": "x"}, ["asset"], 12])
def test_malformed_image_returns_validation_error_not_server_failure(
    client, auth_headers, admin_headers, invalid
):
    result(
        client.post(
            ROOT, headers=auth_headers, json=body("groups", name="Bad image", image_url=invalid)
        ),
        422,
    )
    row = result(client.post(ROOT, headers=auth_headers, json=body("groups", name="Review image")))
    result(action(client, admin_headers, row, "draft", changes={"image_url": invalid}), 422)


def test_website_and_date_reuse_public_profile_validation(client, auth_headers):
    result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=body("groups", name="Bad URL", official_website="not a URL"),
        ),
        422,
    )
    result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=body("groups", name="Bad date", release_date="20200101"),
        ),
        422,
    )
    result(
        client.post(
            ROOT,
            headers=auth_headers,
            json=body("groups", name="Good URL", official_website="https://example.test"),
        )
    )
