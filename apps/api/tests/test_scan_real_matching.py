from __future__ import annotations

import io
import json

import cv2
import numpy as np
import pytest
from conftest import scan_artwork
from PIL import Image, ImageEnhance
from sqlalchemy import select

from app.core.config import get_settings
from app.core.database import SessionLocal
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.models import Card, ScanFeedback, UserCollectionItem


def upload(client, headers, image):
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=82)
    return client.post(
        "/api/v1/scan/recognize",
        headers=headers,
        files={"image": ("cards.jpg", buffer.getvalue(), "image/jpeg")},
    )


def confirm(client, headers, session, items):
    return client.post(
        f"/api/v1/scan/sessions/{session['session_id']}/confirm",
        headers=headers,
        json={"cards": items},
    )


def test_empty_and_legacy_index_never_fabricate_matches(client, auth_headers):
    assert client.get("/api/v1/scan/status").json()["data"]["available"] is False
    result = upload(client, auth_headers, scan_artwork(1))
    assert result.status_code == 503
    assert result.json()["error_code"] == "SCAN_INDEX_UNAVAILABLE"
    get_settings().card_matcher_index_path.write_text(
        json.dumps([{"card_id": "card-aria-01", "face_embedding": [1, 2, 3]}])
    )
    assert client.get("/api/v1/scan/status").json()["data"]["legacy_index_count"] == 1
    assert upload(client, auth_headers, scan_artwork(1)).status_code == 503


def test_index_photo_with_table_background_matches_card_only(client, auth_headers, scan_index):
    photo = Image.new("RGB", (700, 700), "#202020")
    photo.paste(scan_index["card-aria-01"], (150, 70))
    entry = CardMatcherAdapter.index_entry(
        "card-aria-01", photo, "http://testserver/media/card-aria-01.png"
    )
    get_settings().card_matcher_index_path.write_text(json.dumps([entry]))
    result = upload(client, auth_headers, scan_index["card-aria-01"]).json()["data"][
        "detected_cards"
    ][0]
    assert result["candidates"][0]["card"]["id"] == "card-aria-01"


@pytest.mark.parametrize("rotation", [0, 90, 180, 270])
def test_real_matching_under_rotation_resize_and_exposure(
    client, auth_headers, scan_index, rotation
):
    image = ImageEnhance.Brightness(scan_index["card-aria-01"]).enhance(0.8)
    image = image.resize((288, 416)).rotate(rotation, expand=True)
    response = upload(client, auth_headers, image)
    assert response.status_code == 200, response.text
    result = response.json()["data"]["detected_cards"][0]
    assert result["candidates"][0]["card"]["id"] == "card-aria-01"
    assert result["candidates"][0]["similarity"] >= 0.9
    assert result["crop_image_path"].startswith("http")
    assert result["user_confirmed_card_id"] is None


def test_perspective_card_and_unknown_do_not_break_other_results(client, auth_headers, scan_index):
    canvas = np.full((680, 1250, 3), 32, dtype=np.uint8)
    src = np.float32([[0, 0], [359, 0], [359, 519], [0, 519]])
    corners = np.float32([[50, 70], [370, 100], [400, 580], [60, 610]])
    transform = cv2.getPerspectiveTransform(src, corners)
    card = np.asarray(scan_index["card-aria-01"])
    warped = cv2.warpPerspective(card, transform, (1250, 680))
    mask = cv2.warpPerspective(np.full((520, 360), 255, np.uint8), transform, (1250, 680))
    canvas[mask > 0] = warped[mask > 0]
    image = Image.fromarray(canvas)
    image.paste(scan_index["card-lin-01"], (450, 70))
    image.paste(scan_artwork(999), (850, 70))
    response = upload(client, auth_headers, image)
    assert response.status_code == 200, response.text
    results = response.json()["data"]["detected_cards"]
    assert len(results) == 3
    assert {d["candidates"][0]["card"]["id"] for d in results if d["candidates"]} == set(scan_index)
    assert sum(d["recognition_status"] == "unrecognized" for d in results) == 1


def test_duplicate_physical_cards_retry_and_history(client, auth_headers, scan_index):
    image = Image.new("RGB", (850, 640), "#202020")
    for x in (35, 445):
        image.paste(scan_index["card-aria-01"], (x, 50))
    response = upload(client, auth_headers, image)
    assert response.status_code == 200, response.text
    session = response.json()["data"]
    assert len(session["detected_cards"]) == 2
    items = [
        {"detected_card_id": d["detected_card_id"], "card_id": "card-aria-01"}
        for d in session["detected_cards"]
    ]
    first = confirm(client, auth_headers, session, items)
    assert first.json()["data"] == {"added_count": 2, "quantities": {"card-aria-01": 3}}
    retry = confirm(client, auth_headers, session, items)
    assert retry.json()["data"] == {"added_count": 0, "quantities": {"card-aria-01": 3}}
    changed = confirm(client, auth_headers, session, [{**items[0], "card_id": "card-lin-01"}])
    assert changed.status_code == 409
    history = client.get("/api/v1/scan/history", headers=auth_headers).json()["data"]["items"][0]
    assert all(d["owned_added"] for d in history["detected_cards"])


def test_unknown_feedback_and_wishlist_only(client, auth_headers, scan_index):
    session = upload(client, auth_headers, Image.new("RGB", (360, 520), "white")).json()["data"]
    detected = session["detected_cards"][0]
    assert detected["recognition_status"] == "unrecognized"
    assert detected["candidates"] == []
    result = confirm(
        client,
        auth_headers,
        session,
        [
            {
                "detected_card_id": detected["detected_card_id"],
                "card_id": "card-lin-01",
                "selected": False,
                "add_to_wishlist": True,
            }
        ],
    )
    assert result.json()["data"]["added_count"] == 0
    history = client.get("/api/v1/scan/history", headers=auth_headers).json()["data"]["items"][0]
    manual = history["detected_cards"][0]
    assert manual["owned_added"] is False
    assert manual["user_confirmed_card_id"] == "card-lin-01"
    assert manual["candidates"][0]["card"]["id"] == "card-lin-01"
    assert manual["candidates"][0]["similarity"] == 0
    feedback = client.post(
        "/api/v1/scan/feedback",
        headers=auth_headers,
        data={
            "metadata": json.dumps(
                {
                    "scan_session_id": session["session_id"],
                    "detected_card_id": detected["detected_card_id"],
                    "user_id": "forged",
                    "ai_candidates": [{"card_id": "fake", "similarity": 1}],
                }
            )
        },
    )
    assert feedback.status_code == 200
    with SessionLocal() as db:
        saved = db.scalar(select(ScanFeedback))
        assert saved.payload["user_id"] == "current-user"
        assert saved.payload["ai_candidates"] == []
        assert saved.payload["crop_image_url"]
        assert (
            db.scalar(
                select(UserCollectionItem).where(
                    UserCollectionItem.card_id == "card-lin-01",
                    UserCollectionItem.user_id == "current-user",
                )
            )
            is None
        )


def test_validation_hidden_cards_ownership_and_atomic_batch(
    client, auth_headers, admin_headers, scan_index
):
    session = upload(client, auth_headers, scan_index["card-aria-01"]).json()["data"]
    item = {
        "detected_card_id": session["detected_cards"][0]["detected_card_id"],
        "card_id": "card-aria-01",
    }
    assert confirm(client, admin_headers, session, [item]).status_code == 404
    assert confirm(client, auth_headers, session, [item, item]).status_code == 422
    assert (
        confirm(
            client, auth_headers, session, [item, {**item, "detected_card_id": "missing"}]
        ).status_code
        == 404
    )
    with SessionLocal() as db:
        assert (
            db.scalar(
                select(UserCollectionItem).where(UserCollectionItem.card_id == "card-aria-01")
            ).quantity
            == 1
        )
        db.get(Card, "card-aria-01").status = "OFFLINE"
        db.commit()
    offline = upload(client, auth_headers, scan_index["card-aria-01"]).json()["data"]
    assert offline["detected_cards"][0]["candidates"][0]["card"]["id"] == "card-aria-01"
    assert client.get("/api/v1/catalog/cards/card-aria-01").status_code == 404
    historical = client.get("/api/v1/catalog/cards/card-aria-01", headers=auth_headers)
    assert historical.status_code == 200
    assert historical.json()["data"]["availability_notice"]
    assert (
        client.get("/api/v1/catalog/cards/card-aria-01", headers=admin_headers).status_code == 404
    )
    assert confirm(client, auth_headers, session, [item]).status_code == 200
    with SessionLocal() as db:
        db.get(Card, "card-aria-01").status = "ARCHIVED"
        db.commit()
    archived = upload(client, auth_headers, scan_index["card-aria-01"]).json()["data"]
    assert all(not d["candidates"] for d in archived["detected_cards"])
    assert confirm(client, auth_headers, session, [item]).status_code == 404
    assert (
        client.post(
            "/api/v1/scan/recognize",
            headers=auth_headers,
            files={"image": ("bad.jpg", b"not image")},
        ).status_code
        == 400
    )


def test_region_failure_is_isolated(client, auth_headers, scan_index, monkeypatch):
    image = Image.new("RGB", (850, 640), "#202020")
    image.paste(scan_index["card-aria-01"], (35, 50))
    image.paste(scan_index["card-lin-01"], (445, 50))
    original = CardMatcherAdapter.rank
    calls = []

    def sometimes_fail(self, crop, known):
        calls.append(1)
        if len(calls) == 1:
            raise RuntimeError("One crop failed")
        return original(self, crop, known)

    monkeypatch.setattr(CardMatcherAdapter, "rank", sometimes_fail)
    results = upload(client, auth_headers, image).json()["data"]["detected_cards"]
    assert len(results) == 2
    assert sum(bool(d["candidates"]) for d in results) == 1


def test_stale_index_and_request_limits(client, auth_headers, scan_index, monkeypatch):
    with SessionLocal() as db:
        for card_id in scan_index:
            db.get(Card, card_id).image_url = "http://testserver/media/replaced.png"
        db.commit()
    assert client.get("/api/v1/scan/status").json()["data"]["available"] is False
    monkeypatch.setattr(get_settings(), "scan_max_bytes", 10)
    response = client.post(
        "/api/v1/scan/recognize",
        headers=auth_headers,
        files={"image": ("large.jpg", b"a" * 11)},
    )
    assert response.status_code == 413
    response = client.post(
        "/api/v1/scan/recognize",
        headers=auth_headers,
        files={"image": ("empty.jpg", b"")},
    )
    assert response.json()["error_code"] == "EMPTY_FILE"


@pytest.mark.parametrize("metadata", ["[]", '{"scan_session_id": []}', "not json"])
def test_invalid_feedback_is_rejected(client, auth_headers, metadata):
    response = client.post(
        "/api/v1/scan/feedback", headers=auth_headers, data={"metadata": metadata}
    )
    assert response.status_code == 400
    assert response.json()["error_code"] == "INVALID_FEEDBACK"


def test_card_count_limit(client, auth_headers, scan_index, monkeypatch):
    monkeypatch.setattr(get_settings(), "card_detector_max_cards", 1)
    image = Image.new("RGB", (850, 640), "#202020")
    image.paste(scan_index["card-aria-01"], (35, 50))
    image.paste(scan_index["card-lin-01"], (445, 50))
    response = upload(client, auth_headers, image)
    assert response.status_code == 400
    assert response.json()["error_code"] == "TOO_MANY_CARDS"


def test_ambiguous_matches_require_explicit_confirmation(client, auth_headers, scan_index):
    entries = [
        CardMatcherAdapter.index_entry(
            card_id, scan_index["card-aria-01"], f"http://testserver/media/{card_id}.png"
        )
        for card_id in scan_index
    ]
    get_settings().card_matcher_index_path.write_text(json.dumps(entries))
    result = upload(client, auth_headers, scan_index["card-aria-01"]).json()["data"]
    detected = result["detected_cards"][0]
    assert len(detected["candidates"]) == 2
    assert detected["recognition_status"] == "needs_confirmation"
    assert detected["user_confirmed_card_id"] is None
    assert detected["owned_added"] is False


def test_featureless_reference_is_rejected():
    with pytest.raises(ValueError, match="卡图细节不足"):
        CardMatcherAdapter.index_entry("blank", Image.new("RGB", (360, 520), "white"), "blank.png")
