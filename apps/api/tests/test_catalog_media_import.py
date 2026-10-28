import io
import socket

import pytest
from PIL import Image, UnidentifiedImageError
from sqlalchemy import select

from app.admin_models import ContentMetadata
from app.core.config import get_settings
from app.core.database import SessionLocal
from app.future_models import OutboxEvent
from app.modules.catalog import media_import as media
from app.modules.catalog import media_worker as worker

SOURCE = "https://upload.wikimedia.org/wikipedia/commons/a/ab/Portrait.jpg"
ROOT = "/api/v1/admin/console"


def seed_portrait():
    with SessionLocal() as db:
        meta = db.scalar(
            select(ContentMetadata).where(
                ContentMetadata.entity_type == "idols", ContentMetadata.entity_id == "idol-aria"
            )
        )
        if not meta:
            meta = ContentMetadata(entity_type="idols", entity_id="idol-aria", operator_id="test")
            db.add(meta)
        meta.status = "PUBLISHED"
        meta.data = {"image_url": SOURCE}
        assert media.queue_images(db, "idols", "idol-aria", meta.data) == 1
        db.commit()
        assert media.queue_images(db, "idols", "idol-aria", meta.data) == 0


def fixture_image():
    buffer = io.BytesIO()
    Image.new("RGB", (1200, 1800), "purple").save(buffer, "JPEG")
    return buffer.getvalue()


def test_download_once_public_uses_stored_file_and_thumbnail(client, monkeypatch):
    seed_portrait()
    calls = []
    monkeypatch.setattr(media, "download_image", lambda url: calls.append(url) or fixture_image())
    before = client.get("/api/v1/catalog/idols/idol-aria").json()["data"]
    assert before["image_url"] is None
    assert worker.process_pending() == 1
    after = client.get("/api/v1/catalog/idols/idol-aria").json()["data"]
    assert after["image_url"].startswith("http://testserver/media/catalog-managed/")
    assert "/thumbs/" in after["thumbnail_url"]
    assert client.get(after["image_url"]).status_code == 200
    response = client.get(after["thumbnail_url"])
    assert response.status_code == 200
    assert max(Image.open(io.BytesIO(response.content)).size) == 384
    assert worker.process_pending() == 0
    assert calls == [SOURCE]
    with SessionLocal() as db:
        assert media.backfill(db) == 0
        event = db.scalar(select(OutboxEvent).where(OutboxEvent.event_type == media.EVENT))
        assert event.payload["source_url"] == SOURCE
        assert event.payload["state"] == "ready"


def test_failed_download_backoff_and_admin_retry(client, admin_headers, auth_headers, monkeypatch):
    seed_portrait()
    monkeypatch.setattr(
        worker, "store_image", lambda _: (_ for _ in ()).throw(ValueError("offline"))
    )
    assert worker.process_pending() == 0
    url = ROOT + "/media/idols/idol-aria"
    assert client.get(url, headers=auth_headers).status_code == 401
    task = client.get(url, headers=admin_headers).json()["data"]["items"][0]
    assert task["state"] == "retrying" and task["attempts"] == 1
    worker.process_pending()
    assert client.get(url, headers=admin_headers).json()["data"]["items"][0]["attempts"] == 1
    assert (
        client.post(ROOT + f"/media/tasks/{task['id']}/retry", headers=admin_headers).status_code
        == 200
    )
    monkeypatch.setattr(media, "download_image", lambda _: fixture_image())
    monkeypatch.setattr(worker, "store_image", media.store_image)
    assert worker.process_pending() == 1
    assert (
        client.post(ROOT + f"/media/tasks/{task['id']}/retry", headers=admin_headers).status_code
        == 409
    )


def test_newer_admin_image_is_never_overwritten(monkeypatch):
    seed_portrait()
    replacement = "http://testserver/media/new-upload.png"

    def during_download(_):
        with SessionLocal() as db:
            row = db.scalar(select(ContentMetadata).where(ContentMetadata.entity_id == "idol-aria"))
            row.data = {**row.data, "image_url": replacement}
            db.commit()
        return "http://testserver/media/old.webp", "http://testserver/media/thumb.webp"

    monkeypatch.setattr(worker, "store_image", during_download)
    assert worker.process_pending() == 0
    with SessionLocal() as db:
        _, _, data = media.target_data(db, "idols", "idol-aria")
        assert data["image_url"] == replacement
        assert (
            db.scalar(select(OutboxEvent).where(OutboxEvent.event_type == media.EVENT)).payload[
                "state"
            ]
            == "superseded"
        )


@pytest.mark.parametrize(
    "source",
    [
        "http://upload.wikimedia.org/a.jpg",
        "https://127.0.0.1/a.jpg",
        "https://upload.wikimedia.org@127.0.0.1/a.jpg",
        "https://evil.example/a.jpg",
        "file:///etc/passwd",
        "https://upload.wikimedia.org:8443/a.jpg",
    ],
)
def test_source_allowlist_rejects_unsafe_input(source):
    with pytest.raises(ValueError):
        media.validate_remote(source)


def test_dns_private_and_non_images_rejected(monkeypatch):
    monkeypatch.setattr(socket, "getaddrinfo", lambda *a, **kw: [(0, 0, 0, "", ("10.0.0.1", 443))])
    with pytest.raises(ValueError, match="内网"):
        media.validate_remote(SOURCE)
    monkeypatch.setattr(media, "download_image", lambda _: b"<html>not an image</html>")
    with pytest.raises(UnidentifiedImageError):
        media.store_image(SOURCE)
    monkeypatch.setattr(media, "MAX_PIXELS", 10)
    monkeypatch.setattr(media, "download_image", lambda _: fixture_image())
    with pytest.raises(ValueError, match="像素"):
        media.store_image(SOURCE)


def test_save_entity_queues_without_downloading(client, admin_headers, monkeypatch):
    monkeypatch.setattr(media, "download_image", lambda _: pytest.fail("must not download in API"))
    response = client.post(
        ROOT + "/entities/groups",
        headers=admin_headers,
        json={"name": "Transfer test", "image_url": SOURCE},
    )
    assert response.status_code == 200, response.text
    entity_id = response.json()["data"]["id"]
    tasks = client.get(ROOT + f"/media/groups/{entity_id}", headers=admin_headers).json()["data"][
        "items"
    ]
    assert len(tasks) == 1 and tasks[0]["state"] == "pending"


def test_card_ingestion_queues_scan_index_after_transfer(client, admin_headers, monkeypatch):
    from test_admin_console import create

    from app.models import Card

    card = create(client, admin_headers, image_url=SOURCE)
    assert card["image_url"] == SOURCE  # admin keeps the original
    monkeypatch.setattr(media, "download_image", lambda _: fixture_image())
    assert worker.process_pending() == 1
    with SessionLocal() as db:
        row = db.get(Card, card["id"])
        assert media.owned_image(row.image_url)
        event = db.scalar(
            select(OutboxEvent).where(OutboxEvent.event_type == "catalog.card.image.updated")
        )
        assert event.payload["image_url"] == row.image_url


def test_owned_media_is_preserved(monkeypatch, tmp_path):
    monkeypatch.setattr(get_settings(), "local_media_root", tmp_path)
    path = tmp_path / "upload.jpg"
    path.write_bytes(fixture_image())
    source = get_settings().public_media_base_url + "/upload.jpg"
    stored, thumbnail = media.store_image(source)
    assert stored == source and "/thumbs/" in thumbnail
    assert path.read_bytes() == fixture_image()


@pytest.mark.parametrize("kind", ["groups", "idols", "albums", "events", "others"])
def test_import_spreadsheet_queues_transfers_and_preserves_review(
    client, admin_headers, kind, monkeypatch
):
    from test_catalog_bulk import confirm, preview

    row = {"name": "Image import", "image_url": SOURCE}
    if kind != "groups":
        row["group_name"] = "LUMINA"
    if kind == "events":
        row["city"] = "Seoul"
    task = preview(client, admin_headers, kind, [row])
    assert task["errors"] == []
    with SessionLocal() as db:
        assert not db.scalar(select(OutboxEvent).where(OutboxEvent.event_type == media.EVENT))
    result = confirm(client, admin_headers, task)
    assert result.status_code == 200, result.text
    entity_id = result.json()["data"]["rows"][0]["created_id"]
    monkeypatch.setattr(media, "download_image", lambda _: fixture_image())
    assert worker.process_pending() >= 1
    with SessionLocal() as db:
        _, meta, data = media.target_data(db, kind, entity_id)
        assert media.owned_image(data["image_url"])
        assert meta.status == "DRAFT"  # Ingestion never publishes catalog content.


def test_exhausted_crashed_task_can_be_retried(client, admin_headers):
    seed_portrait()
    with SessionLocal() as db:
        event = db.scalar(select(OutboxEvent).where(OutboxEvent.event_type == media.EVENT))
        event.publish_attempts = 5
        event.payload = {**event.payload, "state": "downloading"}
        task_id = event.id
        db.commit()
    assert worker.process_pending() == 0
    assert (
        client.post(ROOT + f"/media/tasks/{task_id}/retry", headers=admin_headers).status_code
        == 200
    )
