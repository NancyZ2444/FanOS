import io

from PIL import Image

from app.core.config import get_settings
from app.core.database import SessionLocal
from app.modules.catalog import media_import

ROOT = "/api/v1/admin/console"


def test_other_cover_upload_uses_local_storage_and_survives_edit(
    client, admin_headers, tmp_path, monkeypatch
):
    monkeypatch.setattr(get_settings(), "local_media_root", tmp_path)
    image = io.BytesIO()
    Image.new("RGB", (160, 200), "#7255bb").save(image, "PNG")
    uploaded = client.post(
        ROOT + "/uploads",
        headers=admin_headers,
        files={"file": ("cover.png", image.getvalue(), "image/png")},
    )
    assert uploaded.status_code == 200, uploaded.text
    url = uploaded.json()["data"]["url"]
    assert media_import.owned_image(url)
    assert media_import._local_path(url).is_file()
    payload = {"name": "本地封面来源", "group_id": "group-lumina", "image_url": url}
    created = client.post(ROOT + "/entities/others", headers=admin_headers, json=payload)
    assert created.status_code == 200, created.text
    item = created.json()["data"]
    assert item["image_url"] == url
    edited = client.put(
        ROOT + "/entities/others/" + item["id"],
        headers=admin_headers,
        json={**payload, "name": "保留原有封面"},
    )
    assert edited.status_code == 200, edited.text
    assert edited.json()["data"]["image_url"] == url

    def no_remote_download(*args, **kwargs):
        raise AssertionError("An uploaded local cover must not download a remote image")

    monkeypatch.setattr(media_import.httpx, "stream", no_remote_download)
    stored, thumbnail = media_import.store_image(url)
    assert stored == url and media_import.owned_image(thumbnail)
    with SessionLocal() as db:
        _, _, data = media_import.target_data(db, "others", item["id"])
        assert data["image_url"] == url
