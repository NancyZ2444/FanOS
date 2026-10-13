"""Source selectors and trusted structured metadata for unrecognized-card feedback."""

import json

import pytest
from sqlalchemy import select

from app.admin_models import ContentMetadata
from app.core.database import SessionLocal
from app.models import (
    CatalogAlbum,
    DetectedCard,
    ScanCandidate,
    ScanFeedback,
    ScanSession,
    UserCollectionItem,
    UserWishlistItem,
)
from app.modules.admin.catalog_extensions import CatalogRecord


def _session():
    with SessionLocal() as db:
        session = ScanSession(
            user_id="current-user", original_image_url="http://testserver/media/scan.jpg"
        )
        db.add(session)
        db.flush()
        detected = DetectedCard(
            scan_session_id=session.id,
            crop_image_url="http://testserver/media/crop.jpg",
            crop_region={"x": 0.1, "y": 0.1, "width": 0.3, "height": 0.5},
            recognition_status="unrecognized",
        )
        db.add(detected)
        db.flush()
        db.add(
            ScanCandidate(
                detected_card_id=detected.id,
                card_id="card-aria-01",
                similarity=0.43,
                rank=1,
            )
        )
        db.commit()
        return {"scan_session_id": session.id, "detected_card_id": detected.id}


def _options(client, auth_headers, source="专辑", **params):
    return client.get(
        "/api/v1/scan/feedback-options",
        headers=auth_headers,
        params={"source": source, **params},
    )


def _submit(client, auth_headers, metadata):
    return client.post(
        "/api/v1/scan/feedback", headers=auth_headers, data={"metadata": json.dumps(metadata)}
    )


def test_batch_wishlist_then_owned_preserves_independent_quantities_and_retry(client, auth_headers):
    context = _session()
    ids = [context["detected_card_id"]]
    with SessionLocal() as db:
        for _ in range(2):
            item = DetectedCard(
                scan_session_id=context["scan_session_id"],
                crop_region={"x": 0.4, "y": 0.1, "width": 0.2, "height": 0.3},
                recognition_status="recommended",
            )
            db.add(item)
            db.flush()
            ids.append(item.id)
        original = db.scalar(
            select(UserCollectionItem).where(
                UserCollectionItem.user_id == "current-user",
                UserCollectionItem.card_id == "card-aria-01",
            )
        ).quantity
        db.commit()
    endpoint = f"/api/v1/scan/sessions/{context['scan_session_id']}/confirm"
    cards = [{"detected_card_id": item, "card_id": "card-aria-01"} for item in ids]
    response = client.post(
        endpoint,
        headers=auth_headers,
        json={"cards": [{**card, "selected": False, "add_to_wishlist": True} for card in cards]},
    )
    assert response.status_code == 200 and response.json()["data"]["added_count"] == 0
    with SessionLocal() as db:
        assert (
            db.scalar(
                select(UserCollectionItem).where(
                    UserCollectionItem.user_id == "current-user",
                    UserCollectionItem.card_id == "card-aria-01",
                )
            ).quantity
            == original
        )
        assert (
            len(
                db.scalars(
                    select(UserWishlistItem).where(
                        UserWishlistItem.user_id == "current-user",
                        UserWishlistItem.card_id == "card-aria-01",
                    )
                ).all()
            )
            == 1
        )
        assert all(db.get(DetectedCard, item).owned_added_at is None for item in ids)
    owned = client.post(endpoint, headers=auth_headers, json={"cards": cards})
    assert owned.status_code == 200 and owned.json()["data"]["added_count"] == 3
    assert owned.json()["data"]["quantities"]["card-aria-01"] == original + 3
    retry = client.post(endpoint, headers=auth_headers, json={"cards": cards})
    assert retry.status_code == 200 and retry.json()["data"]["added_count"] == 0
    assert retry.json()["data"]["quantities"]["card-aria-01"] == original + 3


def test_source_options_filter_actors_and_legacy_versions(client, auth_headers):
    params = {"group_id": "group-lumina", "idol_id": "idol-aria"}
    response = _options(client, auth_headers, **params)
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["source_mode"] == "KNOWN"
    assert {row["id"] for row in data["items"]} == {"album-starlit", "album-blue-hour"}
    album = next(row for row in data["items"] if row["id"] == "album-starlit")
    assert album["entity_type"] == "ALBUM"
    assert album["subtitle"] and album["versions"]
    assert all(version["id"].startswith("legacy_version_") for version in album["versions"])
    repeated = _options(client, auth_headers, **params).json()["data"]["items"]
    assert (
        album["versions"] == next(row for row in repeated if row["id"] == album["id"])["versions"]
    )
    # A public selector is read-only; it must not materialize operational records.
    with SessionLocal() as db:
        assert db.scalars(select(CatalogRecord).where(CatalogRecord.kind == "versions")).all() == []
    assert (
        _options(client, auth_headers, group_id="group-lumina", idol_id="idol-yuna").status_code
        == 400
    )


@pytest.mark.parametrize(
    ("source", "group_id", "expected"),
    [
        ("签售", "group-lumina", {"event-starlit-seoul"}),
        ("演唱会", "group-nova", {"event-afterglow-tour", "event-afterglow-shanghai"}),
        ("活动", "group-lumina", {"event-starlit-seoul", "event-blue-hour-popup"}),
    ],
)
def test_event_categories_return_relevant_official_entities(
    client, auth_headers, source, group_id, expected
):
    response = _options(client, auth_headers, source, group_id=group_id)
    assert response.status_code == 200, response.text
    assert {row["id"] for row in response.json()["data"]["items"]} == expected
    assert all(row["entity_type"] == "EVENT" for row in response.json()["data"]["items"])


def test_options_hide_unpublished_sources_versions_and_filter_solo_artists(client, auth_headers):
    with SessionLocal() as db:
        db.get(CatalogAlbum, "album-blue-hour").is_published = False
        db.add(
            ContentMetadata(
                entity_type="albums",
                entity_id="album-starlit",
                status="PUBLISHED",
                operator_id="admin-user",
                data={"artists": [{"type": "idols", "id": "idol-lin"}]},
            )
        )
        db.add_all(
            [
                CatalogRecord(
                    id="version-public",
                    kind="versions",
                    entity_type="albums",
                    entity_id="album-starlit",
                    status="DRAFT",
                    data={"name": "Official Ver."},
                ),
                CatalogRecord(
                    id="version-archived",
                    kind="versions",
                    entity_type="albums",
                    entity_id="album-starlit",
                    status="ARCHIVED",
                    data={"name": "Archived Ver."},
                ),
            ]
        )
        db.commit()
    assert _options(client, auth_headers, idol_id="idol-aria").json()["data"]["items"] == []
    selected = _options(client, auth_headers, idol_id="idol-lin").json()["data"]["items"]
    assert len(selected) == 1 and selected[0]["id"] == "album-starlit"
    assert "version-public" in {v["id"] for v in selected[0]["versions"]}
    assert "version-archived" not in {v["id"] for v in selected[0]["versions"]}
    with SessionLocal() as db:
        meta = db.scalar(
            select(ContentMetadata).where(ContentMetadata.entity_id == "album-starlit")
        )
        meta.status = "DRAFT"
        db.commit()
    assert _options(client, auth_headers, idol_id="idol-lin").json()["data"]["items"] == []


def test_feedback_persists_trusted_source_version_and_recognition_context(client, auth_headers):
    options = _options(client, auth_headers, group_id="group-lumina").json()["data"]["items"]
    album = next(row for row in options if row["id"] == "album-starlit")
    version = album["versions"][0]
    metadata = {
        **_session(),
        "group_id": "group-lumina",
        "idol_id": "idol-aria",
        "source": "专辑",
        "source_mode": "KNOWN",
        "source_entity_type": "ALBUM",
        "source_entity_id": album["id"],
        "source_version_id": version["id"],
        "source_name": "Forged client name",
        "source_version_name": "Forged client version",
        "ai_candidates": [{"card_id": "card-yuna-01", "similarity": 1}],
        "user_id": "admin-user",
        "original_image_url": "http://example.com/forged.jpg",
        "notes": "请核对官方版本",
    }
    response = _submit(client, auth_headers, metadata)
    assert response.status_code == 200, response.text
    feedback_id = response.json()["data"]["feedback_id"]
    detail = client.get(f"/api/v1/scan/feedback/{feedback_id}", headers=auth_headers).json()["data"]
    assert detail["source_name"] == album["name"]
    assert detail["source_version_name"] == version["name"]
    assert detail["source_mode"] == "KNOWN"
    assert detail["source_entity_id"] == album["id"]
    assert detail["source_version_id"] == version["id"]
    assert detail["group_id"] == "group-lumina" and detail["idol_id"] == "idol-aria"
    with SessionLocal() as db:
        data = db.get(ScanFeedback, feedback_id).payload
        assert data["user_id"] == "current-user"
        assert data["original_image_url"] == "http://testserver/media/scan.jpg"
        assert data["ai_candidates"] == [{"card_id": "card-aria-01", "similarity": 0.43}]


@pytest.mark.parametrize(
    "changes",
    [
        {"source_entity_type": "EVENT"},
        {"source_entity_id": "album-bloom"},
        {"source_version_id": "missing-version"},
        {"source_mode": "OTHER"},
        {"source_mode": "UNCERTAIN"},
        {"source": "签售"},
    ],
)
def test_invalid_structured_source_references_are_rejected(client, auth_headers, changes):
    metadata = {
        **_session(),
        "group_id": "group-lumina",
        "idol_id": "idol-aria",
        "source": "专辑",
        "source_mode": "KNOWN",
        "source_entity_type": "ALBUM",
        "source_entity_id": "album-starlit",
        **changes,
    }
    response = _submit(client, auth_headers, metadata)
    assert response.status_code == 400, response.text
    assert response.json()["error_code"] == "INVALID_FEEDBACK"
    with SessionLocal() as db:
        assert db.scalars(select(ScanFeedback)).all() == []


def test_unpublished_source_and_version_cannot_be_submitted(client, auth_headers):
    metadata = {
        **_session(),
        "source": "专辑",
        "source_mode": "KNOWN",
        "source_entity_type": "ALBUM",
        "source_entity_id": "album-starlit",
    }
    with SessionLocal() as db:
        db.get(CatalogAlbum, "album-starlit").is_published = False
        db.commit()
    assert _submit(client, auth_headers, metadata).status_code == 400
    with SessionLocal() as db:
        db.get(CatalogAlbum, "album-starlit").is_published = True
        db.add(
            CatalogRecord(
                id="version-foreign",
                kind="versions",
                entity_type="albums",
                entity_id="album-bloom",
                data={"name": "Other Album Ver."},
            )
        )
        db.commit()
    assert (
        _submit(
            client, auth_headers, {**metadata, "source_version_id": "version-foreign"}
        ).status_code
        == 400
    )


def test_unknown_other_and_legacy_category_feedback_remain_compatible(client, auth_headers):
    session = _session()
    for source, mode in [("不确定", "UNCERTAIN"), ("其他", "OTHER")]:
        data = _options(client, auth_headers, source).json()["data"]
        assert data["source_mode"] == ("KNOWN" if source == "其他" else mode)
        assert bool(data["items"]) == (source == "其他")
        response = _submit(
            client,
            auth_headers,
            {**session, "source": source, "source_mode": mode, "notes": "已知但资料暂缺"},
        )
        assert response.status_code == 200, response.text
    assert _submit(client, auth_headers, {**session, "source": "专辑"}).status_code == 200
    assert _submit(client, auth_headers, session).status_code == 200
    history = client.get("/api/v1/scan/feedback", headers=auth_headers).json()["data"]["items"]
    assert len(history) == 4
    assert {item["source_mode"] for item in history} == {"KNOWN", "OTHER", "UNCERTAIN"}


def test_source_selector_auth_and_parameter_validation(client, auth_headers):
    assert client.get("/api/v1/scan/feedback-options", params={"source": "专辑"}).status_code == 401
    assert _options(client, auth_headers, "invalid").status_code == 422
    assert _options(client, auth_headers, group_id="missing").status_code == 400
    assert _options(client, auth_headers, "其他", group_id="group-lumina").status_code == 200
