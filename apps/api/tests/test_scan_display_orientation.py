"""Crop display rotation never changes matching evidence or original coordinates."""

import io

import numpy as np
import pytest
from conftest import scan_artwork
from PIL import Image

from app.core.database import SessionLocal
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.integrations.card_matcher.portrait_detector import PortraitDetector
from app.integrations.card_matcher.visual import display_orientation, features, similarity
from app.integrations.storage import LocalStorage
from app.models import DetectedCard, ScanSession
from app.modules.scan.service import session_payload


@pytest.mark.parametrize("turns", [0, 1, 2, 3])
def test_verified_artwork_orientation_is_clockwise_display_correction(turns):
    reference = scan_artwork(37)
    query = reference.rotate(turns * 90, expand=True)
    score, evidence = similarity(features(query), features(reference))
    assert score >= 0.9
    assert evidence["display_rotation_quarter_turns"] == turns
    corrected = query.rotate(-evidence["display_rotation_quarter_turns"] * 90, expand=True)
    assert np.array_equal(np.asarray(corrected), np.asarray(reference))


def test_ambiguous_or_reflected_geometry_has_no_orientation_hint():
    corners = np.float32([[0, 0], [100, 0], [100, 150], [0, 150]])
    assert display_orientation(corners[[1, 0, 3, 2]]) == {}
    rotation = np.float32([[2**-0.5, -(2**-0.5)], [2**-0.5, 2**-0.5]])
    assert display_orientation(corners @ rotation) == {}
    assert display_orientation(np.zeros((4, 2))) == {}
    assert display_orientation(np.full((4, 2), np.nan)) == {}


@pytest.mark.parametrize("turns", [0, 1, 2, 3])
def test_unmatched_portrait_orientation_uses_real_high_confidence_evidence(turns):
    data = pytest.importorskip("skimage.data")
    portrait = Image.fromarray(data.astronaut()).crop((110, 20, 370, 395)).resize((230, 332))
    assert (
        PortraitDetector().display_rotation_quarter_turns(portrait.rotate(turns * 90, expand=True))
        == turns
    )


def test_uncertain_portrait_scores_do_not_guess_direction(monkeypatch):
    detector = PortraitDetector()
    image = Image.new("RGB", (320, 200), "white")
    assert detector.display_rotation_quarter_turns(image) is None
    monkeypatch.setattr(detector, "_score", lambda *args, **kwargs: 0.92)
    assert detector.display_rotation_quarter_turns(image) is None


def detect_photo(client, headers, photo):
    buffer = io.BytesIO()
    photo.save(buffer, format="PNG")
    response = client.post(
        "/api/v1/scan/detect",
        headers=headers,
        files={"image": ("photo.png", buffer.getvalue(), "image/png")},
    )
    assert response.status_code == 200, response.text
    return response.json()["data"]


def test_selected_scan_persists_hint_without_rotating_source_crop_or_overlay(
    client, auth_headers, scan_index
):
    detected = detect_photo(
        client, auth_headers, scan_index["card-aria-01"].rotate(90, expand=True)
    )
    before = detected["detected_cards"][0]
    storage = LocalStorage()
    pixels = storage.read_bytes(before["crop_image_path"])
    response = client.post(
        f"/api/v1/scan/sessions/{detected['session_id']}/recognize",
        headers=auth_headers,
        json={"detected_card_ids": [before["detected_card_id"]]},
    )
    assert response.status_code == 200, response.text
    row = response.json()["data"]["detected_cards"][0]
    assert row["display_rotation_quarter_turns"] == 1
    assert row["candidates"][0]["scores"]["display_rotation_quarter_turns"] == 1
    assert row["crop_region"] == before["crop_region"]
    assert row["crop_image_path"] == before["crop_image_path"]
    assert storage.read_bytes(row["crop_image_path"]) == pixels
    history = client.get("/api/v1/scan/history", headers=auth_headers).json()["data"]["items"][0]
    assert history["detected_cards"][0]["display_rotation_quarter_turns"] == 1


def test_unmatched_portrait_hint_preserves_empty_candidates_and_status(
    client, auth_headers, scan_index, monkeypatch
):
    detected = detect_photo(client, auth_headers, scan_index["card-aria-01"])
    before = detected["detected_cards"][0]
    monkeypatch.setattr(CardMatcherAdapter, "rank", lambda *args: [])
    monkeypatch.setattr(PortraitDetector, "display_rotation_quarter_turns", lambda *args: 3)
    response = client.post(
        f"/api/v1/scan/sessions/{detected['session_id']}/recognize",
        headers=auth_headers,
        json={"detected_card_ids": [before["detected_card_id"]]},
    )
    assert response.status_code == 200, response.text
    row = response.json()["data"]["detected_cards"][0]
    assert row["recognition_status"] == "unrecognized"
    assert row["candidates"] == []
    assert row["display_rotation_quarter_turns"] == 3
    assert all(row["crop_region"][key] == value for key, value in before["crop_region"].items())


def test_confirmed_candidate_direction_wins_without_suppressing_similar_candidates(
    client, auth_headers, scan_index, monkeypatch
):
    detected = detect_photo(client, auth_headers, scan_index["card-aria-01"])
    row = detected["detected_cards"][0]
    monkeypatch.setattr(
        CardMatcherAdapter,
        "rank",
        lambda *args: [
            {
                "card_id": "card-aria-01",
                "similarity": 0.59,
                "feature_scores": {"display_rotation_quarter_turns": 1},
            },
            {
                "card_id": "card-lin-01",
                "similarity": 0.55,
                "feature_scores": {"display_rotation_quarter_turns": 2},
            },
        ],
    )
    response = client.post(
        f"/api/v1/scan/sessions/{detected['session_id']}/recognize",
        headers=auth_headers,
        json={"detected_card_ids": [row["detected_card_id"]]},
    )
    matched = response.json()["data"]["detected_cards"][0]
    assert matched["recognition_status"] == "unrecognized"
    assert len(matched["candidates"]) == 2  # Never hide a real candidate due to the status label.
    assert matched["display_rotation_quarter_turns"] == 1
    with SessionLocal() as db:
        stored = db.get(DetectedCard, row["detected_card_id"])
        stored.user_confirmed_card_id = "card-lin-01"
        db.commit()
        payload = session_payload(db, db.get(ScanSession, detected["session_id"]))
        assert payload["detected_cards"][0]["display_rotation_quarter_turns"] == 2
