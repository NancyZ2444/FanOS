from uuid import uuid4

import pytest

from app.admin_models import ContentMetadata
from app.core.database import SessionLocal
from app.models import User
from app.modules.admin.catalog_extensions import CatalogRecord
from app.modules.catalog.taxonomy_models import CatalogOther
from app.modules.feedback.models import Feedback

ROOT = "/api/v1/feedback/objects"
TARGETS = [
    ("cards", "card-aria-01"),
    ("groups", "group-lumina"),
    ("idols", "idol-aria"),
    ("albums", "album-starlit"),
    ("events", "event-starlit-seoul"),
    ("others", "other-credit"),
    ("versions", "version-credit"),
]


def setup_targets():
    with SessionLocal() as db:
        db.add(CatalogOther(id="other-credit", name="真实其他来源", is_published=True))
        db.add(
            CatalogRecord(
                id="version-credit",
                kind="versions",
                entity_type="albums",
                entity_id="album-starlit",
                status="PUBLISHED",
                data={"name": "真实专辑版本"},
            )
        )
        db.commit()


def included(entity_kind, entity_id, **changes):
    values = {
        "user_id": "current-user",
        "request_key": str(uuid4()),
        "kind": "CORRECTION",
        "entity_type": entity_kind,
        "entity_id": entity_id,
        "status": "PROCESSED",
        "result": "INCLUDED",
        "review": {"decisions": [{"key": "name", "decision": "ACCEPT"}]},
    }
    return Feedback(**{**values, **changes})


def credits(client, kind, entity_id):
    response = client.get(f"{ROOT}/{kind}/{entity_id}/contributors")
    assert response.status_code == 200, response.text
    return response.json()["data"]["items"]


@pytest.mark.parametrize(("kind", "entity_id"), TARGETS)
def test_official_only_is_empty_and_real_adopted_user_is_shown(client, kind, entity_id):
    setup_targets()
    assert credits(client, kind, entity_id) == []
    with SessionLocal() as db:
        db.add(included(kind, entity_id))
        db.add(included(kind, entity_id))  # Multiple adopted fields/revisions, one person.
        db.commit()
        name = db.get(User, "current-user").display_name
    items = credits(client, kind, entity_id)
    assert len(items) == 1
    assert items[0]["user_id"] == "current-user"
    assert items[0]["name"] == name
    assert items[0]["profile_available"] is True
    assert items[0]["source_type"] == "USER_SUBMITTED"


@pytest.mark.parametrize(
    "changes",
    [
        {"status": "PENDING", "result": "PENDING"},
        {"status": "PROCESSING", "result": "PENDING"},
        {"result": "NOT_INCLUDED"},
        {"result": "NEEDS_INFO"},
        {"review": {"decisions": [{"key": "name", "decision": "REJECT"}]}},
        {"review": {}},
        {"kind": "MISSING_CATALOG", "review": {"adopted_fields": []}},
    ],
)
def test_pending_rejected_or_non_adopted_feedback_is_never_a_credit(client, changes):
    with SessionLocal() as db:
        db.add(included("albums", "album-starlit", **changes))
        db.commit()
    assert credits(client, "albums", "album-starlit") == []


def test_published_missing_catalog_credits_only_adopted_fields(client):
    with SessionLocal() as db:
        db.add(
            included(
                "albums",
                "album-starlit",
                kind="MISSING_CATALOG",
                review={"adopted_fields": ["name"]},
            )
        )
        db.commit()
    assert credits(client, "albums", "album-starlit")[0]["user_id"] == "current-user"


def test_profile_initialization_platform_editor_and_unadopted_revision_are_not_credits(client):
    # Reading legacy data initializes a real system revision, not a contribution.
    assert client.get("/api/v1/catalog/profiles/idols/idol-aria").status_code == 200
    with SessionLocal() as db:
        db.add(
            CatalogRecord(
                kind="profile_versions",
                entity_type="idols",
                entity_id="idol-aria",
                status="PUBLISHED",
                data={
                    "source": "PLATFORM",
                    "author": {"id": "admin-demo", "name": "后台管理员"},
                    "changes": [{"key": "name"}],
                },
            )
        )
        db.commit()
    assert credits(client, "idols", "idol-aria") == []


def test_legacy_adopted_user_review_is_kept_but_admin_operator_is_not_credited(client):
    with SessionLocal() as db:
        db.add(
            CatalogRecord(
                kind="reviews",
                entity_type="groups",
                entity_id="group-lumina",
                status="ACCEPTED",
                data={
                    "contributor": "current-user",
                    "reviewer": "admin-demo",
                    "suggested": {"name": "真实采用名称"},
                },
            )
        )
        db.commit()
    assert [row["user_id"] for row in credits(client, "groups", "group-lumina")] == ["current-user"]


def test_related_profile_revision_requires_a_real_adopted_submission(client):
    with SessionLocal() as db:
        feedback = included("groups", "group-lumina")
        db.add(feedback)
        db.flush()
        db.add(
            CatalogRecord(
                kind="profile_versions",
                entity_type="idols",
                entity_id="idol-aria",
                status="PUBLISHED",
                data={
                    "source": "USER",
                    "author": {"id": "current-user"},
                    "changes": [{"key": "memberships"}],
                    "submission_id": feedback.id,
                },
            )
        )
        db.commit()
        feedback_id = feedback.id
    assert credits(client, "idols", "idol-aria")[0]["user_id"] == "current-user"
    with SessionLocal() as db:
        db.get(Feedback, feedback_id).result = "NOT_INCLUDED"
        db.commit()
    assert credits(client, "idols", "idol-aria") == []


def test_card_legacy_endpoint_keeps_same_verified_attribution(client):
    with SessionLocal() as db:
        db.add(included("cards", "card-aria-01"))
        db.commit()
    original = client.get("/api/v1/feedback/cards/card-aria-01/contributors")
    assert original.status_code == 200, original.text
    assert original.json()["data"]["items"] == credits(client, "cards", "card-aria-01")


def test_inactive_user_credit_has_no_profile_link_and_offline_target_is_private(client):
    with SessionLocal() as db:
        db.add(included("albums", "album-starlit"))
        db.get(User, "current-user").is_active = False
        db.commit()
    item = credits(client, "albums", "album-starlit")[0]
    assert item["name"] == "已注销用户"
    assert item["user_id"] is None and item["profile_available"] is False
    with SessionLocal() as db:
        db.add(
            ContentMetadata(
                entity_type="albums",
                entity_id="album-starlit",
                status="OFFLINE",
                operator_id="admin-demo",
                data={},
            )
        )
        db.commit()
    assert client.get(f"{ROOT}/albums/album-starlit/contributors").status_code == 404
    assert client.get(f"{ROOT}/secrets/album-starlit/contributors").status_code == 422
