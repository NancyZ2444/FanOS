import io
from unittest.mock import patch

from conftest import scan_artwork
from PIL import Image
from sqlalchemy import func, select

from app.core.database import SessionLocal
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.integrations.storage import LocalStorage
from app.models import ScanCandidate, ScanSession, UserCollectionItem, UserWishlistItem


def detect(client, headers, image):
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return client.post(
        "/api/v1/scan/detect",
        headers=headers,
        files={"image": ("photo.jpg", buffer.getvalue(), "image/jpeg")},
    )


def match(client, headers, session, ids):
    return client.post(
        f"/api/v1/scan/sessions/{session['session_id']}/recognize",
        headers=headers,
        json={"detected_card_ids": ids},
    )


def counts():
    with SessionLocal() as db:
        return tuple(
            db.scalar(select(func.count()).select_from(model))
            for model in (ScanCandidate, UserCollectionItem, UserWishlistItem)
        )


def test_detection_needs_no_index_and_does_not_match_or_add_assets(
    client, auth_headers, allow_synthetic_portraits
):
    before = counts()
    with patch.object(CardMatcherAdapter, "rank", side_effect=AssertionError("Too early")):
        response = detect(client, auth_headers, scan_artwork(1))
    assert response.status_code == 200, response.text
    session = response.json()["data"]
    assert len(session["detected_cards"]) == 1
    region = session["detected_cards"][0]
    assert region["recognition_status"] == "detected"
    assert region["candidates"] == []
    assert LocalStorage().read_bytes(region["crop_image_path"])
    assert counts() == before
    assert client.get("/api/v1/scan/history", headers=auth_headers).json()["data"]["items"] == []
    assert match(client, auth_headers, session, [region["detected_card_id"]]).status_code == 503
    with SessionLocal() as db:
        assert db.get(ScanSession, session["session_id"]).status == "detected"


def test_only_selected_regions_match_and_retry_is_idempotent(client, auth_headers, scan_index):
    photo = Image.new("RGB", (1250, 650), "#202020")
    for x in (35, 440, 845):
        photo.paste(scan_index["card-aria-01"], (x, 50))
    session = detect(client, auth_headers, photo).json()["data"]
    regions = session["detected_cards"]
    assert len(regions) == 3
    ids = [regions[i]["detected_card_id"] for i in (0, 2)]
    before = counts()
    original = CardMatcherAdapter.rank
    calls = []

    def rank(self, *args):
        calls.append(1)
        return original(self, *args)

    with patch.object(CardMatcherAdapter, "rank", rank):
        response = match(client, auth_headers, session, ids)
        assert response.status_code == 200, response.text
        assert match(client, auth_headers, session, ids).json() == response.json()
    assert len(calls) == 2
    cards = response.json()["data"]["detected_cards"]
    assert [r["detected_card_id"] for r in cards] == ids
    assert all(r["candidates"][0]["card"]["id"] == "card-aria-01" for r in cards)
    assert counts()[1:] == before[1:]
    history = client.get("/api/v1/scan/history", headers=auth_headers).json()["data"]["items"][0]
    assert len(history["detected_cards"]) == 2
    assert match(client, auth_headers, session, [regions[1]["detected_card_id"]]).status_code == 409


def test_selection_validation_and_ownership(client, auth_headers, second_app_headers, scan_index):
    session = detect(client, auth_headers, scan_index["card-aria-01"]).json()["data"]
    card_id = session["detected_cards"][0]["detected_card_id"]
    assert match(client, auth_headers, session, []).status_code == 422
    assert match(client, auth_headers, session, [card_id, card_id]).status_code == 422
    assert match(client, auth_headers, session, ["not-in-this-photo"]).status_code == 400
    assert match(client, second_app_headers, session, [card_id]).status_code == 404


def test_missing_crop_rolls_back_and_can_retry(client, auth_headers, scan_index):
    session = detect(client, auth_headers, scan_index["card-aria-01"]).json()["data"]
    ids = [r["detected_card_id"] for r in session["detected_cards"]]
    with patch.object(LocalStorage, "read_bytes", side_effect=OSError("Unavailable")):
        assert match(client, auth_headers, session, ids).status_code == 503
    with SessionLocal() as db:
        assert db.get(ScanSession, session["session_id"]).status == "detected"
    assert match(client, auth_headers, session, ids).status_code == 200


def test_storage_rejects_foreign_urls_and_path_traversal():
    import pytest

    for url in [
        "http://evil.example/crop.jpg",
        "http://testserver/media/../secret",
        "http://testserver/media/%2e%2e/secret",
        "http://testserver/media//secret",
    ]:
        with pytest.raises(ValueError):
            LocalStorage().read_bytes(url)


def test_failed_object_retry_preserves_other_results_and_numbering(
    client, auth_headers, scan_index
):
    photo = Image.new("RGB", (1250, 650), "#202020")
    for x in (35, 440, 845):
        photo.paste(scan_index["card-aria-01"], (x, 50))
    session = detect(client, auth_headers, photo).json()["data"]
    ids = [r["detected_card_id"] for r in session["detected_cards"]]
    original = CardMatcherAdapter.rank
    calls = []

    def fail_middle(self, *args):
        calls.append(1)
        if len(calls) == 2:
            raise RuntimeError("temporary matcher failure")
        return original(self, *args)

    with patch.object(CardMatcherAdapter, "rank", fail_middle):
        response = match(client, auth_headers, session, ids)
    assert response.status_code == 200, response.text
    rows = response.json()["data"]["detected_cards"]
    assert [r["detected_card_id"] for r in rows] == ids
    assert rows[1]["recognition_status"] == "failed"
    assert rows[1]["candidates"] == []
    before = counts()
    with patch.object(CardMatcherAdapter, "rank", autospec=True, side_effect=original) as retry:
        response = match(client, auth_headers, session, [ids[1]])
    assert response.status_code == 200, response.text
    assert retry.call_count == 1
    retried = response.json()["data"]["detected_cards"]
    assert retried[0] == rows[0] and retried[2] == rows[2]
    assert retried[1]["recognition_status"] != "failed"
    assert counts()[1:] == before[1:]
