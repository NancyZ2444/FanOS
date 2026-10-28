"""An exhausted index job can recover without changing the official card image."""

import io

from conftest import scan_artwork
from sqlalchemy import select

from app.core.database import SessionLocal
from app.future_models import OutboxEvent
from app.integrations.card_matcher.adapter import CardMatcherAdapter, DetectedRegion
from app.integrations.storage import get_storage
from app.models import Card
from app.modules.admin.catalog_jobs import process_pending


def test_retry_indexes_complete_artwork_after_internal_contours_were_mistaken_for_cards(
    client, admin_headers, monkeypatch
):
    image = scan_artwork(157).resize((210, 335))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    url = get_storage().save_bytes(buffer.getvalue(), "front.png", "index-recovery")
    card_id = "card-aria-01"
    with SessionLocal() as db:
        card = db.get(Card, card_id)
        card.image_url = url
        failed = OutboxEvent(
            event_type="catalog.card.image.updated",
            aggregate_type="card",
            aggregate_id=card_id,
            payload={"card_id": card_id, "image_url": url},
            publish_attempts=5,
            last_error="建库照片需仅包含一张小卡，请先裁剪正面图片",
        )
        db.add(failed)
        db.commit()
        failed_id = failed.id

    # These tapered outlines are printed details within one complete card.
    # They must not cause another indexing failure or become the reference art.
    regions = []
    for points in (
        [(4, 24), (88, 16), (30, 160), (4, 170)],
        [(170, 20), (194, 20), (205, 34), (205, 135)],
    ):
        xs, ys = zip(*points, strict=True)
        x, y, right, bottom = min(xs), min(ys), max(xs), max(ys)
        regions.append(
            DetectedRegion(
                x / image.width,
                y / image.height,
                (right - x + 1) / image.width,
                (bottom - y + 1) / image.height,
                image.crop((x, y, right + 1, bottom + 1)),
                [{"x": px / 209, "y": py / 334} for px, py in points],
                image.size,
            )
        )
    monkeypatch.setattr(CardMatcherAdapter, "detect", lambda *_args, **_kwargs: regions)
    assert process_pending() == 0
    response = client.post(
        f"/api/v1/admin/console/scan-index/{card_id}/retry", headers=admin_headers
    )
    assert response.status_code == 200, response.text
    assert process_pending() == 1
    adapter = CardMatcherAdapter()
    indexed = adapter.indexed({card_id: url})
    assert len(indexed) == 1
    assert indexed[0]["visual"]["size"] == [210, 335]
    ranked = adapter.rank(image.resize((105, 168)), {card_id: url})
    assert ranked[0]["card_id"] == card_id
    assert ranked[0]["similarity"] >= 0.9
    with SessionLocal() as db:
        assert db.get(Card, card_id).image_url == url
        old_job = db.get(OutboxEvent, failed_id)
        assert old_job.publish_attempts == 5 and old_job.last_error
        jobs = list(
            db.scalars(
                select(OutboxEvent).where(
                    OutboxEvent.event_type == "catalog.card.image.updated",
                    OutboxEvent.aggregate_id == card_id,
                )
            )
        )
        assert len(jobs) == 2
        successful = next(job for job in jobs if job.id != failed_id)
        assert successful.published_at is not None and successful.last_error is None
