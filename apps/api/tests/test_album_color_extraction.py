from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from io import BytesIO
from uuid import uuid4

from PIL import Image
from sqlalchemy import func, select

from app.album_models import AlbumColorExtraction, AlbumSettings
from app.core.config import get_settings
from app.core.database import SessionLocal
from app.integrations.storage import get_storage
from app.models import Card
from app.modules.albums import service

ENDPOINT = "/api/v1/albums/color-extractions"


def picture(color="#AC4F82"):
    stream = BytesIO()
    Image.new("RGB", (100, 100), color).save(stream, format="PNG")
    return stream.getvalue()


def upload(client, headers, *, request_id=None, content=None):
    return client.post(
        ENDPOINT,
        headers=headers,
        data={"request_id": request_id or str(uuid4())},
        files={"file": ("photo.png", picture() if content is None else content, "image/png")},
    )


def count():
    with SessionLocal() as db:
        return db.scalar(select(func.count()).select_from(AlbumColorExtraction))


def configure(**limits):
    with SessionLocal() as db:
        settings = service.limits(db)
        row = db.get(AlbumSettings, "global")
        if not row:
            row = AlbumSettings(id="global")
            db.add(row)
        row.config = {**settings, **limits}
        db.commit()


def test_color_analysis_success_retry_and_no_photo_storage(client, auth_headers):
    before = set(get_settings().local_media_root.rglob("*"))
    request_id = str(uuid4())
    first = upload(client, auth_headers, request_id=request_id)
    assert first.status_code == 200, first.text
    result = first.json()["data"]
    assert result["colors"] == ["#AC4F82"]
    assert result["quota"]["color_extraction"]["daily_used"] == 1
    retry = upload(client, auth_headers, request_id=request_id, content=b"not reprocessed")
    assert retry.status_code == 200, retry.text
    assert retry.json()["data"]["colors"] == result["colors"]
    assert count() == 1
    assert set(get_settings().local_media_root.rglob("*")) == before


def test_invalid_and_transparent_pictures_do_not_consume(client, auth_headers):
    for content in (b"", b"not an image", b"<svg></svg>"):
        assert upload(client, auth_headers, content=content).status_code == 422
    stream = BytesIO()
    Image.new("RGBA", (10, 10), (20, 40, 60, 0)).save(stream, format="PNG")
    assert upload(client, auth_headers, content=stream.getvalue()).status_code == 422
    assert count() == 0


def test_color_analysis_has_daily_and_monthly_limits(client, auth_headers):
    configure(normal_color_daily=1, normal_color_monthly=2)
    request_id = str(uuid4())
    assert upload(client, auth_headers, request_id=request_id).status_code == 200
    response = upload(client, auth_headers)
    assert response.status_code == 409
    assert "今日" in response.json()["message"]
    assert upload(client, auth_headers, request_id=request_id).status_code == 200
    configure(normal_color_daily=3, normal_color_monthly=1)
    response = upload(client, auth_headers)
    assert response.status_code == 409
    assert "本月" in response.json()["message"]
    assert count() == 1


def test_color_quota_uses_shanghai_day_and_month_boundary(client, auth_headers, monkeypatch):
    instant = datetime(2026, 10, 31, 16, 0, tzinfo=UTC)  # Beijing November 1 midnight
    monkeypatch.setattr(service, "utcnow", lambda: instant)
    with SessionLocal() as db:
        db.add_all(
            [
                AlbumColorExtraction(
                    user_id="current-user",
                    request_id=str(uuid4()),
                    colors=["#000000"],
                    created_at=datetime(2026, 10, 31, 15, 59, tzinfo=UTC),
                ),
                AlbumColorExtraction(
                    user_id="current-user",
                    request_id=str(uuid4()),
                    colors=["#FFFFFF"],
                    created_at=instant,
                ),
            ]
        )
        db.commit()
    response = client.get("/api/v1/albums/quota", headers=auth_headers)
    assert response.status_code == 200
    quota = response.json()["data"]["color_extraction"]
    assert quota["timezone"] == "Asia/Shanghai"
    assert quota["daily_used"] == quota["monthly_used"] == 1


def test_existing_managed_card_is_checked_and_analyzed(client, auth_headers):
    with SessionLocal() as db:
        card = db.get(Card, "card-aria-01")
        card.image_url = get_storage().save_bytes(picture("#123456"), "color.png", "test-colors")
        db.commit()
    response = client.post(
        ENDPOINT,
        headers=auth_headers,
        data={"request_id": str(uuid4()), "card_id": "card-aria-01"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["data"]["colors"] == ["#123456"]
    with SessionLocal() as db:
        db.get(Card, "card-aria-01").status = "OFFLINE"
        db.commit()
    response = client.post(
        ENDPOINT,
        headers=auth_headers,
        data={"request_id": str(uuid4()), "card_id": "card-aria-01"},
    )
    assert response.status_code == 422
    assert count() == 1


def test_untrusted_or_missing_card_images_do_not_consume(client, auth_headers):
    for source in ("http://127.0.0.1/private", "https://example.org/photo.png", None):
        with SessionLocal() as db:
            db.get(Card, "card-aria-01").image_url = source
            db.commit()
        response = client.post(
            ENDPOINT,
            headers=auth_headers,
            data={"request_id": str(uuid4()), "card_id": "card-aria-01"},
        )
        assert response.status_code == 422
    assert count() == 0


def test_quota_is_not_overspent_by_concurrent_requests(client, auth_headers):
    configure(normal_color_daily=1)
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(lambda _: upload(client, auth_headers), range(3)))
    assert sorted(response.status_code for response in results) == [200, 409, 409]
    assert count() == 1


def test_concurrent_retries_consume_only_one_use(client, auth_headers):
    request_id = str(uuid4())
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(
            pool.map(lambda _: upload(client, auth_headers, request_id=request_id), range(3))
        )
    assert [response.status_code for response in results] == [200, 200, 200]
    assert count() == 1


def test_color_endpoint_requires_auth_and_exactly_one_source(client, auth_headers):
    assert upload(client, {}).status_code == 401
    assert client.post(
        ENDPOINT, headers=auth_headers, data={"request_id": str(uuid4())}
    ).status_code == 422
    assert client.post(
        ENDPOINT,
        headers=auth_headers,
        data={"request_id": str(uuid4()), "card_id": "card-aria-01"},
        files={"file": ("photo.png", picture(), "image/png")},
    ).status_code == 422
    assert count() == 0
