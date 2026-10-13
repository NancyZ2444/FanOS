from io import BytesIO

from PIL import Image
from sqlalchemy import select

from app.admin_models import ContentMetadata
from app.core.config import get_settings
from app.core.database import SessionLocal
from app.modules.catalog import images


def publish_image(filename="portrait-test.png"):
    path = get_settings().local_media_root / filename
    Image.new("RGB", (1600, 2400), "purple").save(path)
    with SessionLocal() as db:
        row = db.scalar(
            select(ContentMetadata).where(
                ContentMetadata.entity_type == "idols", ContentMetadata.entity_id == "idol-aria"
            )
        )
        if row is None:
            row = ContentMetadata(
                entity_type="idols", entity_id="idol-aria", operator_id="admin-demo"
            )
            db.add(row)
        row.status = "PUBLISHED"
        row.data = {"image_url": f"http://testserver/media/{filename}"}
        db.commit()
    return path


def test_thumbnail_cache_version_and_original_preserved(client, monkeypatch):
    original = publish_image()
    data = client.get("/api/v1/catalog/bootstrap").json()["data"]
    idol = next(i for i in data["idols"] if i["id"] == "idol-aria")
    assert idol["image_url"].endswith("portrait-test.png")
    url = idol["thumbnail_url"]
    response = client.get(url)
    assert response.status_code == 200
    with Image.open(BytesIO(response.content)) as image:
        assert max(image.size) == 384
    assert len(response.content) < original.stat().st_size
    monkeypatch.setattr(images, "_source_bytes", lambda _: (_ for _ in ()).throw(AssertionError()))
    assert client.get(url).content == response.content
    assert client.get(url, headers={"If-None-Match": response.headers["etag"]}).status_code == 304
    assert Image.open(original).size == (1600, 2400)
    Image.new("RGB", (800, 1200), "blue").save(original)
    assert images.image_version(idol["image_url"]) not in url


def test_private_portrait_cannot_be_requested_even_when_cached(client):
    publish_image()
    url = "/api/v1/catalog/images/idols/idol-aria"
    assert client.get(url).status_code == 200
    with SessionLocal() as db:
        row = db.scalar(
            select(ContentMetadata).where(
                ContentMetadata.entity_type == "idols", ContentMetadata.entity_id == "idol-aria"
            )
        )
        row.status = "DRAFT"
        db.commit()
    assert client.get(url).status_code == 404
    assert client.get("/api/v1/catalog/images/unknown/idol-aria").status_code == 404


def test_remote_images_use_standard_thumbnail_and_cannot_proxy_private_hosts():
    import pytest

    source = "https://upload.wikimedia.org/wikipedia/commons/a/ab/Test%20image.png"
    assert images.remote_thumbnail_source(source) == (
        "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/"
        "Test%20image.png/500px-Test%20image.png"
    )
    with pytest.raises(ValueError):
        images._source_bytes("http://169.254.169.254/credentials")
    with pytest.raises(ValueError):
        images._source_bytes("http://testserver/media/%2e%2e/private.png")
    assert images.thumbnail_url("idols", "x", "https://other.example/p.png") is None


def test_deferred_external_source_keeps_original_without_network(client, monkeypatch, tmp_path):
    monkeypatch.setattr(get_settings(), "local_media_root", tmp_path)
    monkeypatch.setattr(get_settings(), "catalog_remote_portraits_enabled", False)
    monkeypatch.setattr(
        images.httpx, "stream", lambda *a, **kw: (_ for _ in ()).throw(AssertionError())
    )
    source = "https://upload.wikimedia.org/wikipedia/commons/a/ab/Uncached.png"
    assert images.thumbnail_url("idols", "x", source) is None
    import pytest

    with pytest.raises(ValueError, match="disabled"):
        images._source_bytes(source)


def test_failed_download_does_not_leave_a_cached_error(client, monkeypatch):
    publish_image("retry-portrait.png")
    original = images._source_bytes
    monkeypatch.setattr(images, "_source_bytes", lambda _: (_ for _ in ()).throw(ValueError()))
    url = "/api/v1/catalog/images/idols/idol-aria"
    assert client.get(url).status_code == 503
    monkeypatch.setattr(images, "_source_bytes", original)
    assert client.get(url).status_code == 200


def test_cover_only_relative_upload_is_public_and_can_be_thumbnailed(client):
    path = publish_image("cover-only.png")
    with SessionLocal() as db:
        row = db.scalar(
            select(ContentMetadata).where(
                ContentMetadata.entity_type == "idols", ContentMetadata.entity_id == "idol-aria"
            )
        )
        row.data = {"image_url": " ", "cover_image": "/media/cover-only.png"}
        db.commit()
    idol = next(
        i
        for i in client.get("/api/v1/catalog/bootstrap").json()["data"]["idols"]
        if i["id"] == "idol-aria"
    )
    assert idol["image_url"] == "/media/cover-only.png"
    assert images._local_path(idol["image_url"]) == path.resolve()
    assert client.get(idol["thumbnail_url"]).status_code == 200


def test_group_filter_uses_membership_id_not_primary_group_label(client):
    from datetime import date

    from app.models import GroupMembership

    with SessionLocal() as db:
        db.add(
            GroupMembership(
                group_id="group-aster",
                idol_id="idol-aria",
                status="active",
                start_date=date(2020, 1, 1),
            )
        )
        db.commit()
    items = client.get("/api/v1/catalog/idols?group_id=group-aster").json()["data"]["items"]
    assert "idol-aria" in {item["id"] for item in items}
    assert client.get("/api/v1/catalog/idols?group_id=unknown").json()["data"]["items"] == []


def test_group_members_never_expose_unpublished_idols(client):
    publish_image()
    with SessionLocal() as db:
        row = db.scalar(
            select(ContentMetadata).where(
                ContentMetadata.entity_type == "idols", ContentMetadata.entity_id == "idol-aria"
            )
        )
        row.status = "DRAFT"
        db.commit()
    group = next(
        g
        for g in client.get("/api/v1/catalog/bootstrap").json()["data"]["groups"]
        if g["id"] == "group-lumina"
    )
    assert "idol-aria" not in group["member_ids"]
