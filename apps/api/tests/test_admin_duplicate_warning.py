"""Read-only duplicate hints share the current artwork matcher and include drafts."""

import io

from PIL import Image
from sqlalchemy import func, select
from test_admin_recognition_company_import import scan_artwork

from app.core.database import SessionLocal
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.models import Card, OperationLog, ScanSession

ROOT = "/api/v1/admin/console"


def managed_image(client, headers):
    out = io.BytesIO()
    scan_artwork(711).save(out, "PNG")
    return client.post(
        ROOT + "/uploads",
        headers=headers,
        files={"file": ("card.png", out.getvalue(), "image/png")},
    ).json()["data"]["url"]


def test_similar_uploaded_includes_drafts_and_excludes_self_without_writes(client, admin_headers):
    url = managed_image(client, admin_headers)
    with SessionLocal() as db:
        card = db.get(Card, "card-aria-01")
        card.image_url, card.status = url, "DRAFT"
        db.commit()
        before = [
            (c.id, c.image_url, c.status, c.updated_at.replace(tzinfo=None))
            for c in db.scalars(select(Card))
        ]
        audit = db.scalar(select(func.count()).select_from(OperationLog))
        scans = db.scalar(select(func.count()).select_from(ScanSession))
    response = client.post(ROOT + "/cards/similar", headers=admin_headers, json={"image_url": url})
    assert response.status_code == 200, response.text
    candidates = response.json()["data"]["candidates"]
    assert candidates[0]["card"]["id"] == "card-aria-01" and candidates[0]["score"] >= 0.9
    excluded = client.post(
        ROOT + "/cards/similar",
        headers=admin_headers,
        json={"image_url": url, "exclude_card_id": "card-aria-01"},
    )
    assert excluded.status_code == 200
    assert all(c["card"]["id"] != "card-aria-01" for c in excluded.json()["data"]["candidates"])
    with SessionLocal() as db:
        assert [
            (c.id, c.image_url, c.status, c.updated_at.replace(tzinfo=None))
            for c in db.scalars(select(Card))
        ] == before
        assert db.scalar(select(func.count()).select_from(OperationLog)) == audit
        assert db.scalar(select(func.count()).select_from(ScanSession)) == scans


def test_similarity_failure_does_not_claim_no_duplicates(client, admin_headers, monkeypatch):
    url = managed_image(client, admin_headers)

    def failed(*args):
        raise RuntimeError("model unavailable")

    monkeypatch.setattr(CardMatcherAdapter, "rank", failed)
    response = client.post(ROOT + "/cards/similar", headers=admin_headers, json={"image_url": url})
    assert response.status_code == 503
    assert response.json()["error_code"] == "RECOGNITION_FAILED"


def test_similarity_uses_same_policy_and_reports_unavailable_images(
    client, admin_headers, monkeypatch
):
    url = managed_image(client, admin_headers)
    with SessionLocal() as db:
        db.get(Card, "card-aria-01").image_url = url
        db.commit()
    monkeypatch.setattr(
        CardMatcherAdapter,
        "rank",
        lambda *_: [
            {"card_id": "card-aria-01", "similarity": 0.99, "feature_scores": {"approximate": True}}
        ],
    )
    data = client.post(
        ROOT + "/cards/similar", headers=admin_headers, json={"image_url": url}
    ).json()["data"]
    assert data["status"] == "candidates"
    assert data["unavailable_count"] > 0
    assert data["candidates"][0]["score"] == 0.99


def test_similarity_rejects_external_or_traversal_url_and_app_tokens(
    client, admin_headers, auth_headers
):
    for url in [
        "https://unrelated.invalid/picture.png",
        "http://testserver/media/../../secret",
        "file:///etc/passwd",
    ]:
        response = client.post(
            ROOT + "/cards/similar", headers=admin_headers, json={"image_url": url}
        )
        assert response.status_code == 422
    response = client.post(
        ROOT + "/cards/similar",
        headers=auth_headers,
        json={"image_url": "http://testserver/media/a.png"},
    )
    assert response.status_code == 401


def test_low_detail_image_is_not_reported_as_no_duplicates(client, admin_headers):
    out = io.BytesIO()
    Image.new("RGB", (360, 540), "gray").save(out, "PNG")
    url = client.post(
        ROOT + "/uploads",
        headers=admin_headers,
        files={"file": ("blurred.png", out.getvalue(), "image/png")},
    ).json()["data"]["url"]
    response = client.post(ROOT + "/cards/similar", headers=admin_headers, json={"image_url": url})
    assert response.status_code == 422
    assert response.json()["error_code"] == "INSUFFICIENT_IMAGE_DETAIL"
