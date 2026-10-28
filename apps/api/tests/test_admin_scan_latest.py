"""Admin selection follows the App detector without persisting unselected cards."""

import io

import numpy as np
from PIL import Image
from sqlalchemy import func, select
from test_admin_card_cropping import photo, post_image, selection

from app.core.database import SessionLocal
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.integrations.card_matcher.portrait_detector import PortraitDetectorUnavailable
from app.models import Card
from app.modules.admin.card_cropping import CardCrop, apply_crop
from app.modules.admin.catalog_jobs import storage_bytes


def test_recognition_preview_calls_current_app_geometry(client, admin_headers):
    from skimage import data

    portrait = Image.fromarray(data.astronaut()).crop((110, 20, 370, 395))
    image = Image.new("RGB", (700, 460), "#243043")
    image.paste(portrait, (30, 40))
    image.paste(portrait.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (390, 40))
    raw = io.BytesIO()
    image.save(raw, format="PNG")
    expected = CardMatcherAdapter.detect(raw.getvalue())
    assert len(expected) == 2
    response = client.post(
        "/api/v1/admin/console/cards/crop-preview",
        headers=admin_headers,
        files={"file": ("photo.png", raw.getvalue(), "image/png")},
        data={"mode": "recognition"},
    )
    assert response.status_code == 200, response.text
    regions = response.json()["data"]["regions"]
    assert regions == [{"points": region.corners} for region in expected]


def test_recognition_model_failure_is_not_disguised_as_no_cards(client, admin_headers, monkeypatch):
    def unavailable(raw, *, require_person):
        assert require_person
        raise PortraitDetectorUnavailable("fixture missing model")

    monkeypatch.setattr(CardMatcherAdapter, "detect", unavailable)
    raw = io.BytesIO()
    photo().save(raw, format="PNG")
    response = client.post(
        "/api/v1/admin/console/cards/crop-preview",
        headers=admin_headers,
        files={"file": ("photo.png", raw.getvalue(), "image/png")},
        data={"mode": "recognition"},
    )
    assert response.status_code == 503
    assert response.json()["error_code"] == "SCAN_DETECTOR_UNAVAILABLE"


def test_explicit_second_card_crop_keeps_only_selected_pixels(client, admin_headers):
    image = Image.new("RGB", (760, 560), "#1c2330")
    image.paste(Image.new("RGB", (320, 480), "red"), (30, 40))
    image.paste(Image.new("RGB", (320, 480), "blue"), (410, 40))
    crop = selection(410, 40, 729, 519, 760, 560)
    with SessionLocal() as db:
        count = db.scalar(select(func.count()).select_from(Card))
    response = post_image(client, admin_headers, "/cards/recognize", image, crop)
    assert response.status_code == 200, response.text
    result = response.json()["data"]
    actual = Image.open(io.BytesIO(storage_bytes(result["image_url"])))
    expected = apply_crop(image, CardCrop.model_validate(crop))
    assert actual.format == "PNG"
    assert np.array_equal(np.asarray(actual), np.asarray(expected))
    assert actual.getpixel((100, 100)) == (0, 0, 255)
    with SessionLocal() as db:
        assert db.scalar(select(func.count()).select_from(Card)) == count


def test_approximate_result_never_auto_navigates_as_exact_match(client, admin_headers, monkeypatch):
    monkeypatch.setattr(
        CardMatcherAdapter,
        "rank",
        lambda *_: [
            {"card_id": "card-aria-01", "similarity": 0.99, "feature_scores": {"approximate": True}}
        ],
    )
    response = post_image(client, admin_headers, "/cards/recognize", photo(), selection())
    assert response.status_code == 200, response.text
    assert response.json()["data"]["status"] == "candidates"
