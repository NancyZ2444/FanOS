"""Selecting a detected card must not re-encode away its matching evidence."""

import io

import numpy as np
import pytest
from PIL import Image

from app.integrations.card_matcher.adapter import CardMatcherAdapter, DetectedRegion
from app.integrations.storage import get_storage


@pytest.mark.parametrize("selected_flow", [False, True])
def test_saved_crop_and_both_matching_flows_preserve_detector_pixels(
    client, auth_headers, scan_index, monkeypatch, selected_flow
):
    crop = scan_index["card-aria-01"].resize((200, 289), Image.Resampling.LANCZOS)
    expected_pixels = np.asarray(crop).copy()
    known = {card_id: f"http://testserver/media/{card_id}.png" for card_id in scan_index}
    expected_ranked = CardMatcherAdapter().rank(crop, known)
    assert expected_ranked[0]["card_id"] == "card-aria-01"
    assert expected_ranked[0]["similarity"] >= 0.9
    region = DetectedRegion(0, 0, 1, 1, crop)
    monkeypatch.setattr(CardMatcherAdapter, "detect", staticmethod(lambda _: [region]))
    original_rank = CardMatcherAdapter.rank
    matched_images = []

    def rank(self, image, cards):
        matched_images.append(np.asarray(image).copy())
        return original_rank(self, image, cards)

    monkeypatch.setattr(CardMatcherAdapter, "rank", rank)
    upload = io.BytesIO()
    crop.save(upload, format="JPEG", quality=90)
    endpoint = "detect" if selected_flow else "recognize"
    response = client.post(
        f"/api/v1/scan/{endpoint}",
        headers=auth_headers,
        files={"image": ("card.jpg", upload.getvalue(), "image/jpeg")},
    )
    assert response.status_code == 200, response.text
    session = response.json()["data"]
    row = session["detected_cards"][0]
    saved = get_storage().read_bytes(row["crop_image_path"])
    assert row["crop_image_path"].endswith(".png")
    with Image.open(io.BytesIO(saved)) as persisted:
        assert persisted.format == "PNG"
        assert np.array_equal(np.asarray(persisted), expected_pixels)
    if selected_flow:
        assert matched_images == []
        response = client.post(
            f"/api/v1/scan/sessions/{session['session_id']}/recognize",
            headers=auth_headers,
            json={"detected_card_ids": [row["detected_card_id"]]},
        )
        assert response.status_code == 200, response.text
        row = response.json()["data"]["detected_cards"][0]
    assert len(matched_images) == 1
    assert np.array_equal(matched_images[0], expected_pixels)
    assert row["recognition_status"] == "recommended"
    assert row["candidates"][0]["similarity"] == pytest.approx(expected_ranked[0]["similarity"])
    assert row["candidates"][0]["scores"] == expected_ranked[0]["feature_scores"]
