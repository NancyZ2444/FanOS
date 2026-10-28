from __future__ import annotations

import io
from uuid import uuid4

from conftest import scan_artwork
from PIL import Image, ImageDraw
from test_feedback_workflow import ROOT as FEEDBACK_ROOT
from test_feedback_workflow import action, result
from test_scan_real_matching import upload

from app.admin_models import ContentMetadata
from app.core.database import SessionLocal
from app.models import CatalogAlbum, CatalogEvent
from app.modules.catalog.taxonomy_models import CatalogOther


def test_published_admin_default_images_reach_every_catalog_contract(client):
    with SessionLocal() as db:
        for kind, entity_id in (("groups", "group-lumina"), ("idols", "idol-aria")):
            db.add(
                ContentMetadata(
                    entity_type=kind,
                    entity_id=entity_id,
                    status="PUBLISHED",
                    operator_id="admin-user",
                    data={"image_url": f"http://testserver/media/{entity_id}.jpg"},
                )
            )
        for model in (CatalogAlbum, CatalogEvent, CatalogOther):
            row = db.query(model).first()
            if isinstance(row, CatalogOther):
                row.legacy_data = {
                    **row.legacy_data,
                    "image_url": f"http://testserver/media/{row.id}.jpg",
                }
            else:
                row.image_url = f"http://testserver/media/{row.id}.jpg"
            if isinstance(row, CatalogAlbum):
                row.front_image_url = None
        db.commit()
    data = client.get("/api/v1/catalog/bootstrap").json()["data"]
    for kind, entity_id in (("groups", "group-lumina"), ("idols", "idol-aria")):
        row = next(item for item in data[kind] if item["id"] == entity_id)
        assert row["image_url"].endswith(entity_id + ".jpg")
        assert (
            client.get(f"/api/v1/catalog/{kind}/{entity_id}").json()["data"]["image_url"]
            == row["image_url"]
        )
    assert next(item for item in data["idols"] if item["id"] == "idol-aria")["group_ids"] == [
        "group-lumina"
    ]
    assert any(item["front_image_url"] for item in data["albums"])
    assert any(item["image_url"] for item in data["events"])
    assert any(item["image_url"] for item in data["others"])


def test_profile_cover_upload_persistence_public_view_removal_and_validation(
    client, auth_headers, second_app_headers
):
    content = io.BytesIO()
    Image.new("RGB", (800, 300), "#8176ca").save(content, "PNG")
    endpoint = "/api/v1/me/profile/images/background"
    assert (
        client.post(
            endpoint, files={"image": ("cover.png", content.getvalue(), "image/png")}
        ).status_code
        == 401
    )
    response = client.post(
        endpoint,
        headers=auth_headers,
        files={"image": ("cover.png", content.getvalue(), "image/png")},
    )
    assert response.status_code == 200, response.text
    url = response.json()["data"]["image_url"]
    assert url.endswith(".jpg")
    assert (
        client.get("/api/v1/me/profile", headers=auth_headers).json()["data"]["background_url"]
        == url
    )
    assert (
        client.get("/api/v1/users/current-user", headers=second_app_headers).json()["data"][
            "background_url"
        ]
        == url
    )
    assert client.get(url.replace("http://testserver", "")).status_code == 200
    assert (
        client.post(
            endpoint,
            headers=auth_headers,
            files={"image": ("fake.jpg", b"not an image", "image/jpeg")},
        ).status_code
        == 400
    )
    assert client.delete(endpoint, headers=auth_headers).status_code == 200
    assert (
        client.get("/api/v1/me/profile", headers=auth_headers).json()["data"]["background_url"]
        is None
    )


def test_favorites_exact_selection_and_invalid_primary_do_not_add_extra_idols(client, auth_headers):
    assert (
        client.put(
            "/api/v1/me/favorites",
            headers=auth_headers,
            json={"idol_ids": ["idol-aria", "idol-lin"], "primary_idol_id": "idol-aria"},
        ).status_code
        == 200
    )
    profile = client.get("/api/v1/me/profile", headers=auth_headers).json()["data"]
    assert profile["favorite_idol_ids"] == ["idol-aria", "idol-lin"]
    assert (
        client.put(
            "/api/v1/me/favorites",
            headers=auth_headers,
            json={"idol_ids": ["idol-aria", "idol-lin"], "primary_idol_id": "idol-yuna"},
        ).status_code
        == 400
    )
    assert client.get("/api/v1/me/profile", headers=auth_headers).json()["data"][
        "favorite_idol_ids"
    ] == ["idol-aria", "idol-lin"]
    assert (
        client.put(
            "/api/v1/me/favorites",
            headers=auth_headers,
            json={"idol_ids": [], "primary_idol_id": None},
        ).status_code
        == 200
    )


def test_scan_excludes_enclosing_album_frame_and_matches_each_card(
    client, auth_headers, scan_index
):
    photo = Image.new("RGB", (1000, 1400), "#252525")
    ImageDraw.Draw(photo).rectangle((25, 25, 975, 1375), fill="#fafafa")
    ids = ["card-aria-01", "card-lin-01", "card-aria-01", "card-lin-01", "card-aria-01", None]
    for card_id, (x, y) in zip(
        ids, [(75, 120), (385, 120), (695, 120), (75, 780), (385, 780), (695, 780)], strict=True
    ):
        photo.paste(
            (scan_index[card_id] if card_id else scan_artwork(999)).resize((245, 355)), (x, y)
        )
    response = upload(client, auth_headers, photo)
    assert response.status_code == 200, response.text
    cards = response.json()["data"]["detected_cards"]
    assert len(cards) == 6
    assert [
        item["candidates"][0]["card"]["id"] if item["candidates"] else None for item in cards
    ] == ids
    assert all(item["crop_region"]["width"] < 0.3 for item in cards)
    assert all(item["user_confirmed_card_id"] is None for item in cards)


def test_feedback_group_membership_history_progress_and_owner_isolation(
    client, auth_headers, admin_headers, second_app_headers, scan_index
):
    session = upload(client, auth_headers, Image.new("RGB", (360, 520), "white")).json()["data"]
    metadata = {
        "scan_session_id": session["session_id"],
        "detected_card_id": session["detected_cards"][0]["detected_card_id"],
        "group_id": "group-lumina",
        "idol_id": "idol-yuna",
        "source_entity_type": "ALBUM",
        "source_entity_id": "album-starlit",
    }
    assert (
        client.post(
            FEEDBACK_ROOT,
            headers=auth_headers,
            json={"kind": "MISSING_CARD", "request_key": str(uuid4()), "missing": metadata},
        ).status_code
        == 400
    )
    metadata.update(idol_id="idol-aria")
    row = result(
        client.post(
            FEEDBACK_ROOT,
            headers=auth_headers,
            json={
                "kind": "MISSING_CARD",
                "request_key": str(uuid4()),
                "missing": metadata,
                "notes": "请确认版本",
            },
        )
    )
    detail_url = f"{FEEDBACK_ROOT}/records/{row['id']}"
    detail = result(client.get(detail_url, headers=auth_headers))
    assert detail["status"] == "PENDING"
    assert detail["submission"]["scan"]["crop_image_url"]
    assert detail["submission"]["notes"] == "请确认版本"
    assert client.get(detail_url, headers=second_app_headers).status_code == 404
    assert result(client.get(FEEDBACK_ROOT, headers=second_app_headers))["items"] == []
    reviewing = result(action(client, admin_headers, row, "start"))
    assert reviewing["status"] == "PROCESSING"
    # Internal progress is deliberately hidden until a public review decision.
    assert result(client.get(detail_url, headers=auth_headers))["status"] == "PENDING"
    owned_before = result(client.get("/api/v1/me/profile", headers=auth_headers))["owned"]
    result(
        action(
            client,
            admin_headers,
            reviewing,
            "match",
            card_id="card-aria-01",
            public_note="已补充对应官方图鉴",
        )
    )
    item = result(client.get(FEEDBACK_ROOT, headers=auth_headers))["items"][0]
    assert item["status"] == "PROCESSED" and item["result"] == "NOT_INCLUDED"
    assert item["entity_id"] == "card-aria-01" and item["target_available"]
    assert item["public_note"] == "已补充对应官方图鉴"
    # Reviewing a suggestion must not silently alter the user's collection.
    assert result(client.get("/api/v1/me/profile", headers=auth_headers))["owned"] == owned_before
