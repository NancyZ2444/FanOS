"""Public display corners must describe the same crop, including after storage."""

import io

import cv2
import numpy as np
import pytest
from conftest import scan_artwork
from PIL import Image

from app.core.database import SessionLocal
from app.integrations.card_matcher.adapter import CardMatcherAdapter, DetectedRegion
from app.models import DetectedCard


def test_public_corners_use_bbox_axes_without_changing_admin_endpoints():
    image = Image.new("RGB", (90, 150))
    region = DetectedRegion(
        0.1,
        0.2,
        0.9,
        0.8,
        image,
        [
            {"x": 10 / 99, "y": 40 / 199},
            {"x": 1, "y": 40 / 199},
            {"x": 1, "y": 1},
            {"x": 10 / 99, "y": 1},
        ],
        (100, 200),
    )
    payload = region.payload()
    expected = [
        {"x": 0.1, "y": 0.2},
        {"x": 0.99, "y": 0.2},
        {"x": 0.99, "y": 0.995},
        {"x": 0.1, "y": 0.995},
    ]
    assert all(
        point == pytest.approx(wanted)
        for point, wanted in zip(payload["corners"], expected, strict=True)
    )
    assert region.corners[2] == {"x": 1, "y": 1}
    for point in payload["corners"]:
        assert payload["x"] - 1e-9 <= point["x"] <= payload["x"] + payload["width"] + 1e-9
        assert payload["y"] - 1e-9 <= point["y"] <= payload["y"] + payload["height"] + 1e-9


def test_old_region_without_corners_retains_rectangle_payload():
    region = DetectedRegion(0, 0, 1, 1, Image.new("RGB", (40, 60)))
    assert region.payload() == {"x": 0, "y": 0, "width": 1, "height": 1}


def test_detect_endpoint_persists_real_quad_for_skewed_card(
    client, auth_headers, allow_synthetic_portraits
):
    artwork = np.asarray(scan_artwork(7))
    corners = np.float32([[90, 70], [415, 105], [385, 585], [55, 555]])
    transform = cv2.getPerspectiveTransform(
        np.float32([[0, 0], [359, 0], [359, 519], [0, 519]]), corners
    )
    warped = cv2.warpPerspective(artwork, transform, (500, 660), borderValue=(32, 32, 32))
    buffer = io.BytesIO()
    Image.fromarray(warped).save(buffer, format="JPEG", quality=92)
    expected = CardMatcherAdapter.detect(buffer.getvalue())[0].payload()
    result = client.post(
        "/api/v1/scan/detect",
        headers=auth_headers,
        files={"image": ("skewed.jpg", buffer.getvalue(), "image/jpeg")},
    )
    assert result.status_code == 200, result.text
    cards = result.json()["data"]["detected_cards"]
    assert len(cards) == 1
    assert cards[0]["crop_region"] == expected
    assert len(expected["corners"]) == 4
    assert abs(expected["corners"][0]["y"] - expected["corners"][1]["y"]) > 0.03
    with SessionLocal() as db:
        assert db.get(DetectedCard, cards[0]["detected_card_id"]).crop_region == expected
