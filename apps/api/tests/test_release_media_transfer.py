import hashlib
import importlib.util
from pathlib import Path

import pytest
from sqlalchemy import select
from test_catalog_media_import import SOURCE, fixture_image, seed_portrait

from app.core.database import SessionLocal
from app.future_models import OutboxEvent
from app.modules.catalog import media_import as media
from scripts import catalog_media_transfer as transfer


def transfer_item(tmp_path):
    content = fixture_image()
    (tmp_path / "portrait.image").write_bytes(content)
    return {
        "kind": "idols",
        "id": "idol-aria",
        "field": "image_url",
        "source_url": SOURCE,
        "name": "Aria",
        "file": "portrait.image",
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def test_offline_transfer_checksum_and_idempotency(client, tmp_path, monkeypatch):
    seed_portrait()
    monkeypatch.setattr(transfer, "validate_remote", lambda _: None)
    item = transfer_item(tmp_path)
    with SessionLocal() as db:
        exported = transfer.export_manifest(db)
        assert any(i["source_url"] == SOURCE for i in exported["items"])
        with pytest.raises(ValueError, match="checksum"):
            transfer.import_item(db, {**item, "sha256": "invalid"}, tmp_path)
        assert transfer.import_item(db, item, tmp_path) == "ready"
        db.commit()
        assert transfer.import_item(db, item, tmp_path) == "unchanged_or_superseded"
        row = db.scalar(select(OutboxEvent).where(OutboxEvent.event_type == media.EVENT))
        assert row.payload["source_url"] == SOURCE
        assert row.payload["transfer"] == "checksum_verified_offline"
        assert media.owned_image(row.payload["stored_url"])


def test_offline_transfer_rejects_path_escape(client, tmp_path, monkeypatch):
    seed_portrait()
    monkeypatch.setattr(transfer, "validate_remote", lambda _: None)
    item = transfer_item(tmp_path)
    with SessionLocal() as db, pytest.raises(ValueError, match="Invalid transfer file"):
        transfer.import_item(db, {**item, "file": "../outside.image"}, tmp_path)


def test_prefetch_preserves_source_identity_and_standard_size():
    path = Path(__file__).resolve().parents[3] / "scripts" / "prefetch-catalog-media.py"
    spec = importlib.util.spec_from_file_location("prefetch_media", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    source = "https://upload.wikimedia.org/wikipedia/commons/f/fa/20230630_Song_Yu-qi.jpg"
    assert module.download_url(source, False) == source
    assert module.download_url(source, True) == (
        "https://upload.wikimedia.org/wikipedia/commons/thumb/f/fa/"
        "20230630_Song_Yu-qi.jpg/960px-20230630_Song_Yu-qi.jpg"
    )
    other = "https://i.scdn.co/image/album-cover"
    assert module.download_url(other, True) == other
    assert "127.0.0.1" not in module.ALLOWED_HOSTS
    assert "i.scdn.co" in module.ALLOWED_HOSTS
