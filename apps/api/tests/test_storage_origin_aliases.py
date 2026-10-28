"""Persisted local media URLs can use loopback aliases without widening ownership."""

import io
from types import SimpleNamespace

import pytest

from app.core.config import get_settings
from app.integrations.storage import LocalStorage, S3Storage, _owned_key
from app.modules.admin.catalog_jobs import storage_bytes


@pytest.mark.parametrize("base_host", ["localhost", "127.0.0.1", "[::1]"])
@pytest.mark.parametrize("url_host", ["localhost", "127.0.0.1", "[::1]"])
def test_local_storage_and_index_worker_read_loopback_aliases(
    tmp_path, monkeypatch, base_host, url_host
):
    settings = get_settings()
    monkeypatch.setattr(settings, "storage_backend", "local")
    monkeypatch.setattr(settings, "local_media_root", tmp_path)
    monkeypatch.setattr(settings, "public_media_base_url", f"http://{base_host}:8000/media")
    (tmp_path / "feedback").mkdir()
    (tmp_path / "feedback/card.jpg").write_bytes(b"reference artwork")
    url = f"http://{url_host}:8000/media/feedback/card.jpg"

    assert LocalStorage().read_bytes(url) == b"reference artwork"
    assert storage_bytes(url) == b"reference artwork"


@pytest.mark.parametrize(
    ("base", "url"),
    [
        ("http://localhost/media", "http://127.0.0.1:80/media/card.jpg"),
        ("http://localhost:80/media", "http://[::1]/media/card.jpg"),
        ("https://localhost/media", "https://[::1]:443/media/card.jpg"),
        ("https://127.0.0.1:443/media", "https://localhost/media/card.jpg"),
    ],
)
def test_loopback_aliases_compare_effective_ports(base, url):
    assert _owned_key(url, base, allow_loopback_aliases=True) == "card.jpg"


@pytest.mark.parametrize(
    "url",
    [
        "http://127.0.0.1:8001/media/card.jpg",
        "http://127.0.0.1/media/card.jpg",
        "https://127.0.0.1:8000/media/card.jpg",
        "http://example.com:8000/media/card.jpg",
        "http://localhost.example.com:8000/media/card.jpg",
        "http://127.0.0.2:8000/media/card.jpg",
        "http://[::ffff:127.0.0.1]:8000/media/card.jpg",
        "http://127.0.0.1:8000/other/card.jpg",
        "http://127.0.0.1:8000/media-extra/card.jpg",
        "http://user@127.0.0.1:8000/media/card.jpg",
        "http://user:password@localhost:8000/media/card.jpg",
        "http://127.0.0.1:8000/media/card.jpg?download=1",
        "http://localhost:8000/media/card.jpg#fragment",
        "http://127.0.0.1:8000/media/../outside.jpg",
        "http://127.0.0.1:8000/media/%2e%2e/outside.jpg",
        "http://127.0.0.1:8000/media/feedback%2f..%2f..%2foutside.jpg",
        "http://127.0.0.1:8000/media/%2foutside.jpg",
        "http://127.0.0.1:8000/media/feedback%5coutside.jpg",
        "http://127.0.0.1:8000/media/card%00.jpg",
        "http://127.0.0.1:8000/media//card.jpg",
        "http://127.0.0.1:8000/media/",
        "\nhttp://127.0.0.1:8000/media/card.jpg",
    ],
)
def test_local_alias_ownership_rejects_other_origins_and_unsafe_paths(url):
    with pytest.raises(ValueError):
        _owned_key(url, "http://localhost:8000/media", allow_loopback_aliases=True)


def test_remote_storage_base_does_not_gain_loopback_aliases():
    with pytest.raises(ValueError):
        _owned_key(
            "https://localhost/media/card.jpg",
            "https://media.example.com/media",
            allow_loopback_aliases=True,
        )
    assert _owned_key(
        "https://media.example.com/media/card.jpg", "https://media.example.com/media"
    ) == "card.jpg"


def test_explicit_port_zero_is_not_the_default_port():
    with pytest.raises(ValueError):
        _owned_key(
            "http://127.0.0.1:0/media/card.jpg",
            "http://localhost/media",
            allow_loopback_aliases=True,
        )


def test_local_media_still_decodes_safe_encoded_keys(tmp_path, monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "local_media_root", tmp_path)
    monkeypatch.setattr(settings, "public_media_base_url", "http://localhost:8000/media")
    (tmp_path / "card image.jpg").write_bytes(b"artwork")
    assert LocalStorage().read_bytes("http://127.0.0.1:8000/media/card%20image.jpg") == b"artwork"


def test_local_aliases_do_not_allow_symlink_escape(tmp_path, monkeypatch):
    root = tmp_path / "media"
    root.mkdir()
    (tmp_path / "outside.jpg").write_bytes(b"outside")
    (root / "card.jpg").symlink_to(tmp_path / "outside.jpg")
    settings = get_settings()
    monkeypatch.setattr(settings, "local_media_root", root)
    monkeypatch.setattr(settings, "public_media_base_url", "http://localhost:8000/media")

    with pytest.raises(ValueError, match="Invalid object path"):
        LocalStorage().read_bytes("http://127.0.0.1:8000/media/card.jpg")


def test_s3_keeps_its_exact_configured_origin_and_bucket():
    calls = []

    def get_object(**kwargs):
        calls.append(kwargs)
        return {"Body": io.BytesIO(b"artwork")}

    storage = S3Storage.__new__(S3Storage)
    storage.settings = SimpleNamespace(
        s3_public_base_url="http://localhost:9000", s3_endpoint_url=None, s3_bucket="cards"
    )
    storage.client = SimpleNamespace(get_object=get_object)

    for url in (
        "http://127.0.0.1:9000/cards/card.jpg",
        "http://localhost:9000/other/card.jpg",
        "http://localhost:9000/cards/../other/card.jpg",
    ):
        with pytest.raises(ValueError):
            storage.read_bytes(url)
    assert calls == []
    assert storage.read_bytes("http://localhost:9000/cards/card.jpg") == b"artwork"
    assert calls == [{"Bucket": "cards", "Key": "card.jpg"}]
