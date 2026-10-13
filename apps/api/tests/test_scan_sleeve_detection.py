"""Transparent binder-page regressions, with no downloaded or human imagery."""

from __future__ import annotations

import io
from urllib.parse import urlparse

import numpy as np
import pytest
from conftest import scan_artwork
from PIL import Image, ImageDraw

from app.core.config import get_settings
from app.integrations.card_matcher.adapter import CardMatcherAdapter


def sleeve_photo(
    rows: int = 3,
    columns: int = 3,
    *,
    empty: tuple[int, int] | None = None,
    unknown: tuple[int, int] | None = None,
    angle: float = 0,
) -> tuple[Image.Image, list[tuple[float, float]], list[str | None]]:
    """Low-contrast rounded cards, clear sleeve seams, glare and clipped neighbors.

    The neutral canvas is close to the artwork's paper color, rather than the
    black/high-contrast background used by earlier separate-card fixtures.
    An empty pocket retains the same seam outline but has no card texture.
    """
    width, height = 220 + columns * 272, 300 + rows * 364
    paper = (227, 229, 226)
    photo = Image.new("RGB", (width, height), paper)
    draw = ImageDraw.Draw(photo)
    draw.rectangle((170, 190, width - 18, height - 25), outline=(193, 195, 193), width=2)
    draw.rectangle((158, 185, 172, height - 10), fill=(204, 205, 201))
    for y in range(235, height - 100, 170):
        draw.ellipse((157, y, 179, y + 22), outline=(156, 159, 156), width=3)
    # Only fragments of the neighboring page are in-frame; these are not full cards.
    photo.paste(scan_artwork(44).resize((230, 332)), (450, -245))
    photo.paste(scan_artwork(45).resize((230, 332)), (-207, 310))
    draw.rectangle((0, 160, width, 179), fill=(207, 195, 184))

    centers: list[tuple[float, float]] = []
    ids: list[str | None] = []
    for row in range(rows):
        for column in range(columns):
            x, y = 204 + column * 272, 250 + row * 364
            draw.rounded_rectangle(
                (x - 6, y - 6, x + 235, y + 337),
                radius=18,
                outline=(212, 214, 211),
                width=2,
            )
            if (row, column) == empty:
                continue
            seed = 999 if (row, column) == unknown else 1 + (row + column) % 2
            if seed == 999:
                # Independent texture: the indexed fixtures share circular
                # print motifs, so a third circle print can legitimately yield
                # a medium-confidence candidate instead of an unknown result.
                artwork = Image.new("RGB", (230, 332), "#365f83")
                unknown_draw = ImageDraw.Draw(artwork)
                unknown_draw.polygon([(35, 45), (198, 125), (65, 285)], fill="#e5ddd6")
                unknown_draw.polygon([(148, 185), (195, 230), (138, 285)], fill="#d1843c")
            else:
                artwork = scan_artwork(seed).resize((230, 332))
            # Plastic haze weakens the edge contrast while preserving matchable detail.
            artwork = Image.blend(artwork, Image.new("RGB", artwork.size, paper), 0.10)
            mask = Image.new("L", artwork.size)
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, 229, 331), radius=14, fill=255)
            photo.paste(artwork, (x, y), mask)
            centers.append((x + 115, y + 166))
            ids.append(None if seed == 999 else ("card-aria-01" if seed == 1 else "card-lin-01"))

    # Continuous translucent sleeve welds can meet the rounded card edge and
    # break the closed quadrilateral assumed by plain contour-only detection.
    draw = ImageDraw.Draw(photo)
    for column in range(columns + 1):
        x = 192 + column * 272
        draw.line((x, 205, x, height - 35), fill=(207, 210, 207), width=2)
        draw.line((x + 3, 205, x + 3, height - 35), fill=(239, 240, 236), width=2)
    for row in range(rows + 1):
        y = 235 + row * 364
        draw.line((185, y, width - 25, y), fill=(207, 210, 207), width=2)
        draw.line((185, y + 3, width - 25, y + 3), fill=(239, 240, 236), width=2)
    glare = Image.new("RGBA", photo.size)
    glare_draw = ImageDraw.Draw(glare)
    glare_draw.polygon(
        [(235, 0), (260, 0), (width - 180, height), (width - 208, height)],
        fill=(255, 255, 255, 24),
    )
    glare_draw.polygon(
        [(width - 220, 0), (width - 202, 0), (350, height), (330, height)],
        fill=(255, 255, 255, 15),
    )
    photo = Image.alpha_composite(photo.convert("RGBA"), glare).convert("RGB")
    noise = np.random.default_rng(62).normal(0, 0.75, (height, width, 1))
    photo = Image.fromarray(
        np.clip(np.asarray(photo).astype(float) + noise, 0, 255).astype(np.uint8)
    )
    if angle:
        photo = photo.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True, fillcolor=paper)
    return photo, centers, ids


def jpeg_bytes(photo: Image.Image) -> bytes:
    buffer = io.BytesIO()
    photo.save(buffer, format="JPEG", quality=88)
    return buffer.getvalue()


@pytest.mark.parametrize(
    ("rows", "columns", "empty", "angle", "expected_count"),
    [
        (3, 3, None, 0, 9),
        (2, 3, None, 0, 6),
        (3, 3, (1, 1), 0, 8),
        (3, 3, None, 4, 9),
        (2, 3, None, -4, 6),
    ],
)
def test_sleeve_detects_observed_cards_without_assuming_nine_slots(
    rows, columns, empty, angle, expected_count
):
    photo, centers, _ = sleeve_photo(rows, columns, empty=empty, angle=angle)
    # This fixture validates sleeve geometry using non-human abstract prints.
    regions = CardMatcherAdapter.detect(jpeg_bytes(photo), require_person=False)
    assert len(regions) == expected_count
    assert len({(item.x, item.y, item.width, item.height) for item in regions}) == expected_count
    for item in regions:
        assert 0.035 < item.width * item.height < 0.18
        assert item.crop.width > 150 and item.crop.height > 240
        assert 0.55 < item.crop.width / item.crop.height < 0.85
    if not angle:
        # Count alone must not pass by finding artwork patches or the binding.
        observed = [(item.x + item.width / 2, item.y + item.height / 2) for item in regions]
        for x, y in centers:
            assert any(
                abs(rx * photo.width - x) < 35 and abs(ry * photo.height - y) < 35
                for rx, ry in observed
            )


def test_nine_sleeve_cards_have_separate_api_crops_and_unknown_is_isolated(
    client, auth_headers, scan_index
):
    photo, _, expected_ids = sleeve_photo(unknown=(2, 2))
    response = client.post(
        "/api/v1/scan/recognize",
        headers=auth_headers,
        files={"image": ("transparent-sleeve-nine.jpg", jpeg_bytes(photo), "image/jpeg")},
    )
    assert response.status_code == 200, response.text
    session = response.json()["data"]
    cards = session["detected_cards"]
    assert len(cards) == 9
    assert len({card["detected_card_id"] for card in cards}) == 9
    assert len({card["crop_image_path"] for card in cards}) == 9
    assert all(card["crop_image_path"] != session["original_image_path"] for card in cards)
    assert all(card["user_confirmed_card_id"] is None and not card["owned_added"] for card in cards)
    assert [
        card["candidates"][0]["card"]["id"] if card["candidates"] else None for card in cards
    ] == expected_ids
    assert sum(card["recognition_status"] == "unrecognized" for card in cards) == 1
    assert all(
        card["crop_region"]["width"] * card["crop_region"]["height"] < 0.18 for card in cards
    )
    for card in cards:
        key = urlparse(card["crop_image_path"]).path.removeprefix("/media/")
        with Image.open(get_settings().local_media_root / key) as crop:
            assert crop.width < photo.width / 2 and crop.height < photo.height / 2
            assert crop.width > 150 and crop.height > 240

    recognized = [card for card in cards if card["recognition_status"] != "unrecognized"]
    result = client.post(
        f"/api/v1/scan/sessions/{session['session_id']}/confirm",
        headers=auth_headers,
        json={
            "cards": [
                {
                    "detected_card_id": card["detected_card_id"],
                    "card_id": card["candidates"][0]["card"]["id"],
                }
                for card in recognized
            ]
        },
    )
    assert result.status_code == 200, result.text
    assert result.json()["data"]["added_count"] == 8
    history = client.get("/api/v1/scan/history", headers=auth_headers).json()["data"]["items"][0]
    assert len(history["detected_cards"]) == 9
    assert sum(card["owned_added"] for card in history["detected_cards"]) == 8
    assert history["detected_cards"][-1]["recognition_status"] == "unrecognized"
    assert history["detected_cards"][-1]["user_confirmed_card_id"] is None
