"""Real CPU model regressions, deliberately not using scan_index's stub gate.

Positive fixtures use scikit-image's bundled NASA astronaut (public domain),
not user/idol photos. Synthetic matching fixtures remain separate.
"""

import io

import pytest
from PIL import Image, ImageDraw

from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.integrations.card_matcher.portrait_detector import (
    PortraitDetector,
    PortraitDetectorUnavailable,
)


def encoded(image):
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


@pytest.fixture
def portrait():
    # Included in the project's existing ai extras; no network downloads.
    data = pytest.importorskip("skimage.data")
    return Image.fromarray(data.astronaut()).crop((110, 20, 370, 395)).resize((230, 332))


@pytest.mark.parametrize("angle", [0, 90, 180, 270])
def test_real_person_gate_accepts_rotated_portrait(portrait, angle):
    assert PortraitDetector().contains_person(portrait.rotate(angle, expand=True))


def keyboard():
    image = Image.new("RGB", (640, 460), "#878882")
    draw = ImageDraw.Draw(image)
    for row in range(4):
        for col in range(8):
            x, y = 12 + col * 78, 15 + row * 92
            draw.rounded_rectangle((x, y, x + 66, y + 80), radius=7, fill="#242522")
            draw.text((x + 20, y + 25), "esc" if col == 0 else str(col), fill="white")
    return image


def test_keyboard_blank_pockets_and_rectangular_artwork_are_not_people():
    detector = PortraitDetector()
    for image in (keyboard(), Image.new("RGB", (230, 332), "#eee8f5")):
        assert not detector.contains_person(image)
        assert CardMatcherAdapter.detect(encoded(image)) == []


def test_single_portrait_with_screen_and_keyboard_distractors(portrait):
    scene = Image.new("RGB", (850, 850), "#363636")
    scene.paste(portrait, (310, 240))
    draw = ImageDraw.Draw(scene)
    draw.rectangle((45, 45, 200, 150), fill="#999999", outline="#dedede", width=8)
    draw.rectangle((630, 640, 820, 780), fill="#999999", outline="#dedede", width=8)
    draw.text((650, 680), "esc", fill="white")
    before = CardMatcherAdapter.detect(encoded(scene), require_person=False)
    after = CardMatcherAdapter.detect(encoded(scene))
    assert len(before) >= 3  # Ensure this scene actually exercises false regions.
    assert len(after) == 1
    region = after[0]
    assert abs(region.x * 850 - 310) < 15
    assert abs(region.y * 850 - 240) < 15
    assert abs(region.width * 850 - 230) < 15
    assert abs(region.height * 850 - 332) < 15


@pytest.mark.parametrize(
    ("rows", "columns", "empty", "angle", "count"),
    [
        (3, 3, None, 0, 9),
        (3, 3, (1, 1), 0, 8),
        (2, 3, None, 4, 6),
    ],
)
def test_real_portraits_in_sleeves_keep_separate_regions(
    portrait, monkeypatch, rows, columns, empty, angle, count
):
    import test_scan_sleeve_detection as sleeve

    monkeypatch.setattr(sleeve, "scan_artwork", lambda seed: portrait)
    photo, _, _ = sleeve.sleeve_photo(rows, columns, empty=empty, angle=angle)
    regions = CardMatcherAdapter.detect(encoded(photo))
    assert len(regions) == count
    assert all(0.035 < region.width * region.height < 0.18 for region in regions)


def test_empty_detection_preserves_photo_but_never_fabricates_one_card(client, auth_headers):
    response = client.post(
        "/api/v1/scan/detect",
        headers=auth_headers,
        files={"image": ("keyboard.jpg", encoded(keyboard()), "image/jpeg")},
    )
    assert response.status_code == 200, response.text
    session = response.json()["data"]
    assert session["detected_cards"] == []
    assert session["original_image_path"]
    assert (
        client.post(
            f"/api/v1/scan/sessions/{session['session_id']}/recognize",
            headers=auth_headers,
            json={"detected_card_ids": []},
        ).status_code
        == 422
    )


def test_missing_model_is_explicit_service_error_not_a_geometry_only_fallback(
    client, auth_headers, monkeypatch
):
    import app.integrations.card_matcher.portrait_detector as detector

    def missing():
        raise PortraitDetectorUnavailable("Missing fixture model")

    monkeypatch.setattr(detector, "_verified_model", missing)
    response = client.post(
        "/api/v1/scan/detect",
        headers=auth_headers,
        files={"image": ("photo.jpg", encoded(keyboard()), "image/jpeg")},
    )
    assert response.status_code == 503
    assert response.json()["error_code"] == "SCAN_DETECTOR_UNAVAILABLE"
    status = client.get("/api/v1/scan/status").json()["data"]
    assert status["detector_available"] is False
    assert "portrait_detector" in status["missing_requirements"]


def test_gate_accepts_multiple_people_in_a_single_crop(portrait):
    group = Image.new("RGB", (460, 664), "#eeeeee")
    group.paste(portrait.resize((184, 266)), (30, 170))
    group.paste(portrait.resize((184, 266)), (230, 170))
    assert PortraitDetector().contains_person(group)
