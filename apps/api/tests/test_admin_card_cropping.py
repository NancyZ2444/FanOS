import base64
import io
import json

import cv2
import numpy as np
import pytest
from conftest import scan_artwork
from PIL import Image
from sqlalchemy import func, select
from test_catalog_bulk import ROOT

from app.core.database import SessionLocal
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.models import Card, OperationLog
from app.modules.admin.card_cropping import CardCrop, apply_crop
from app.modules.admin.catalog_jobs import storage_bytes


def photo(image=None):
    card = image or scan_artwork(711)
    image = Image.new("RGB", (700, 760), "#263343")
    image.paste(card, (160, 100))
    return image


def selection(x=160, y=100, right=519, bottom=619, width=700, height=760):
    return {
        "points": [
            {"x": a / (width - 1), "y": b / (height - 1)}
            for a, b in [(x, y), (right, y), (right, bottom), (x, bottom)]
        ]
    }


def post_image(client, headers, route, image, crop=None, fmt="PNG"):
    buffer = io.BytesIO()
    image.save(buffer, format=fmt, **({"exif": image.getexif()} if fmt == "JPEG" else {}))
    return client.post(
        ROOT + route,
        headers=headers,
        files={"file": ("photo.png", buffer.getvalue(), "image/png")},
        data={"crop": json.dumps(crop)} if crop is not None else {},
    )


def test_preview_detects_background_without_saving_media_or_catalog(client, admin_headers):
    with SessionLocal() as db:
        counts = [
            db.scalar(select(func.count()).select_from(model)) for model in [Card, OperationLog]
        ]
    result = post_image(client, admin_headers, "/cards/crop-preview", photo())
    assert result.status_code == 200, result.text
    data = result.json()["data"]
    assert (data["width"], data["height"]) == (700, 760)
    assert len(data["regions"]) == 1
    expected = selection()["points"]
    assert (
        np.max(
            np.abs(
                np.array([[p["x"], p["y"]] for p in data["regions"][0]["points"]])
                - np.array([[p["x"], p["y"]] for p in expected])
            )
        )
        < 0.02
    )
    with SessionLocal() as db:
        assert counts == [
            db.scalar(select(func.count()).select_from(model)) for model in [Card, OperationLog]
        ]


def test_tilted_card_auto_selection_removes_background(client, admin_headers):
    card = scan_artwork(711)
    points = np.float32([[210, 90], [549, 155], [475, 650], [125, 570]])
    matrix = cv2.getPerspectiveTransform(
        np.float32([[0, 0], [359, 0], [359, 519], [0, 519]]), points
    )
    image = Image.fromarray(
        cv2.warpPerspective(np.asarray(card), matrix, (700, 760), borderValue=(30, 40, 50))
    )
    data = post_image(client, admin_headers, "/cards/crop-preview", image).json()["data"]
    assert len(data["regions"]) == 1
    crop = data["regions"][0]
    selected = np.array([[p["x"] * 699, p["y"] * 759] for p in crop["points"]])
    assert np.max(np.abs(selected - points)) < 8
    result = apply_crop(image, CardCrop.model_validate(crop))
    assert 330 < result.width < 380 and 470 < result.height < 540
    assert np.mean(np.asarray(result)[10:20, 10:20]) > 150


def test_confirmed_crop_matches_existing_and_is_not_detected_again(
    client, admin_headers, scan_index, monkeypatch
):
    def unexpected_detect(_):
        raise AssertionError("Confirmed crop must not be automatically trimmed again")

    monkeypatch.setattr(CardMatcherAdapter, "detect", unexpected_detect)
    response = post_image(
        client, admin_headers, "/cards/recognize", photo(scan_index["card-aria-01"]), selection()
    )
    assert response.status_code == 200, response.text
    result = response.json()["data"]
    assert result["status"] == "matched"
    assert result["candidates"][0]["card"]["id"] == "card-aria-01"
    image = Image.open(io.BytesIO(storage_bytes(result["image_url"])))
    assert image.size == (360, 520)
    with SessionLocal() as db:
        assert db.get(Card, "card-aria-01").image_url == "http://testserver/media/card-aria-01.png"
        log = db.scalar(select(OperationLog).where(OperationLog.action == "catalog.card.recognize"))
        assert log is not None


def test_upload_uses_manual_corners_and_keeps_original_orientation(client, admin_headers):
    image = photo()
    stored = image.transpose(Image.Transpose.ROTATE_90)
    stored.getexif()[274] = 6
    preview = post_image(client, admin_headers, "/cards/crop-preview", stored, fmt="JPEG").json()[
        "data"
    ]
    assert (preview["width"], preview["height"]) == image.size
    thumb = Image.open(io.BytesIO(base64.b64decode(preview["preview_url"].split(",")[1])))
    assert thumb.size == image.size
    response = post_image(client, admin_headers, "/uploads", stored, selection(), fmt="JPEG")
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert (data["width"], data["height"]) == (360, 520)
    result = Image.open(io.BytesIO(storage_bytes(data["url"])))
    assert result.size == (360, 520)
    assert sum(result.getpixel((5, 5))) > 600


@pytest.mark.parametrize(
    "crop",
    [
        {"points": [{"x": -0.1, "y": 0}, {"x": 1, "y": 0}, {"x": 1, "y": 1}, {"x": 0, "y": 1}]},
        {"points": [{"x": 0, "y": 0}, {"x": 1, "y": 1}, {"x": 1, "y": 0}, {"x": 0, "y": 1}]},
        {"points": [{"x": float("nan"), "y": 0}] * 4},
        {"points": [{"x": 0, "y": 0}] * 4},
        selection(160, 100, 161, 101),
    ],
)
def test_invalid_crops_rejected_on_upload_and_recognition(client, admin_headers, crop):
    for path in ["/uploads", "/cards/recognize"]:
        result = post_image(client, admin_headers, path, photo(), crop)
        assert result.status_code == 422
        assert result.json()["message"]


def test_preview_fallback_invalid_photo_and_permission(client, admin_headers, auth_headers):
    blank = post_image(
        client, admin_headers, "/cards/crop-preview", Image.new("RGB", (200, 300), "white")
    )
    assert blank.json()["data"]["regions"] == []
    assert post_image(client, auth_headers, "/cards/crop-preview", photo()).status_code == 403
    assert post_image(client, auth_headers, "/uploads", photo(), selection()).status_code == 403
    bad = client.post(
        ROOT + "/cards/crop-preview",
        headers=admin_headers,
        files={"file": ("bad.png", b"bad", "image/png")},
    )
    assert bad.status_code == 422


def test_cropped_unknown_is_not_replaced_by_catalog_reference_during_index_fill(
    client, admin_headers
):
    reference = post_image(client, admin_headers, "/uploads", scan_artwork(711)).json()["data"][
        "url"
    ]
    with SessionLocal() as db:
        card = db.get(Card, "card-aria-01")
        card.image_url = reference
        card.status = "DRAFT"
        db.commit()
    blank = photo(Image.new("RGB", (360, 520), "white"))
    response = post_image(client, admin_headers, "/cards/recognize", blank, selection())
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["status"] == "incomplete"
    assert data["indexed_count"] == 1
    assert data["candidates"] == []
    saved = Image.open(io.BytesIO(storage_bytes(data["image_url"])))
    assert saved.size == (360, 520)
    assert np.min(np.asarray(saved)) >= 250
