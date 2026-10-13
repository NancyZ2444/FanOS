from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

TEST_ROOT = Path(__file__).resolve().parent
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_ROOT / 'fan_os_test.db'}"
os.environ["LOCAL_MEDIA_ROOT"] = str(TEST_ROOT / "media")
os.environ["PUBLIC_MEDIA_BASE_URL"] = "http://testserver/media"
os.environ["AUTO_SEED"] = "true"
os.environ["CARD_MATCHER_FACE"] = "mock"
os.environ["CARD_MATCHER_BODY"] = "mock"
os.environ["CARD_MATCHER_EXPRESSION"] = "mock"
os.environ["CARD_MATCHER_POSE"] = "mock"
os.environ["CARD_MATCHER_INDEX_PATH"] = str(TEST_ROOT / "cards.json")

from app.core.database import Base, SessionLocal, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.seed import seed_database  # noqa: E402


@pytest.fixture(autouse=True)
def reset_database(tmp_path, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "card_matcher_index_path", tmp_path / "cards.json")
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    with SessionLocal() as db:
        seed_database(db)
    yield


def scan_artwork(seed: int):
    """Non-photographic, reproducible fixtures; no downloaded idol photos."""
    import random

    from PIL import Image, ImageDraw

    randomizer = random.Random(seed)
    image = Image.new("RGB", (360, 520), "#e8e4df")
    draw = ImageDraw.Draw(image)
    for _ in range(90):
        x, y = randomizer.randrange(30, 310), randomizer.randrange(30, 465)
        size = randomizer.randrange(5, 24)
        color = tuple(randomizer.randrange(20, 200) for _ in range(3))
        draw.ellipse((x, y, x + size, y + size), fill=color, outline="black")
    draw.text((45, 480), f"FAN OS TEST {seed}", fill="black")
    return image


@pytest.fixture
def scan_index():
    import json

    from app.core.config import get_settings
    from app.integrations.card_matcher.adapter import CardMatcherAdapter
    from app.models import Card

    images = {"card-aria-01": scan_artwork(1), "card-lin-01": scan_artwork(2)}
    entries = []
    with SessionLocal() as db:
        for card_id, image in images.items():
            url = f"http://testserver/media/{card_id}.png"
            db.get(Card, card_id).image_url = url
            entries.append(CardMatcherAdapter.index_entry(card_id, image, url))
        db.commit()
    get_settings().card_matcher_index_path.write_text(json.dumps(entries))
    return images


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def auth_headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/login",
        json={"method": "phone", "phone": "13800000000", "code": "123456"},
    )
    token = response.json()["data"]["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def admin_headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/login",
        json={"method": "phone", "phone": "13900000000", "code": "123456"},
    )
    token = response.json()["data"]["access_token"]
    return {"Authorization": f"Bearer {token}"}
