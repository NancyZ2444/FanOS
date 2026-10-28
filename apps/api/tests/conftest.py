from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

TEST_ROOT = Path(__file__).resolve().parent
os.environ["DATABASE_URL"] = os.environ.get(
    "FAN_OS_TEST_DATABASE_URL", f"sqlite:///{TEST_ROOT / 'fan_os_test.db'}"
)
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
def allow_synthetic_portraits(monkeypatch):
    """Matching-only tests use abstract prints, not a test of the portrait gate.

    Real-model acceptance/rejection is covered separately in
    test_scan_portrait_detection.py, without this fixture.
    """
    from app.integrations.card_matcher.portrait_detector import PortraitDetector

    monkeypatch.setattr(PortraitDetector, "contains_person", lambda self, image: True)


@pytest.fixture
def scan_index(allow_synthetic_portraits):
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
    from datetime import UTC, datetime, timedelta

    from app.auth_models import AuthState, LoginWhitelist
    from app.core.config import get_settings
    from app.core.security import secret_hash

    with SessionLocal() as db:
        cfg = db.get(AuthState, "test-code:" + get_settings().environment)
        if cfg is None:
            db.add(
                AuthState(
                    id="test-code:" + get_settings().environment,
                    kind="test-config",
                    data={"enabled": True, "code_hash": secret_hash("666666")},
                    version=1,
                )
            )
        else:
            cfg.data = {"enabled": True, "code_hash": secret_hash("666666")}
        db.add(
            LoginWhitelist(
                phone="13800000000",
                environment=get_settings().environment,
                expires_at=datetime.now(UTC) + timedelta(days=1),
                owner="test",
                purpose="isolated fixture",
                updated_by="test",
            )
        )
        db.commit()
    challenge = client.post(
        "/api/v1/auth/sms/challenges", json={"phone": "13800000000", "purpose": "login"}
    ).json()["data"]["challenge_id"]
    response = client.post(
        "/api/v1/auth/login",
        json={
            "method": "phone",
            "phone": "13800000000",
            "code": "666666",
            "challenge_id": challenge,
        },
    )
    token = response.json()["data"]["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def admin_headers(client: TestClient) -> dict[str, str]:
    from app.auth_models import AdminPrincipal
    from app.core.security import secret_hash

    with SessionLocal() as db:
        db.add(
            AdminPrincipal(
                id="admin-principal-test",
                account="fixture-admin",
                display_name="测试管理员",
                password_hash=secret_hash("Fixture-Admin-Password1!"),
                role="admin",
            )
        )
        db.commit()
    response = client.post(
        "/api/v1/admin/auth/login",
        json={"account": "fixture-admin", "password": "Fixture-Admin-Password1!"},
    )
    token = response.json()["data"]["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def admin_actor_headers(client: TestClient):
    """Create independent test principals, then exercise the real admin login boundary."""
    from app.auth_models import AdminPrincipal
    from app.core.security import secret_hash

    def create(role: str, account: str):
        password = "Independent-Test-Password1!"
        with SessionLocal() as db:
            db.add(
                AdminPrincipal(
                    id=account,
                    account=account,
                    display_name=account,
                    role=role,
                    password_hash=secret_hash(password),
                )
            )
            db.commit()
        response = client.post(
            "/api/v1/admin/auth/login", json={"account": account, "password": password}
        )
        assert response.status_code == 200, response.text
        return {"Authorization": "Bearer " + response.json()["data"]["access_token"]}

    return create


@pytest.fixture
def second_app_headers(client: TestClient, monkeypatch):
    """Legacy admin-demo remains an App user, with no administrator authority."""
    from app.modules.auth import providers

    sent = []
    with monkeypatch.context() as scoped:
        scoped.setattr(providers, "send_sms", lambda phone, code: sent.append(code) or "accepted")
        challenge = client.post("/api/v1/auth/sms/challenges", json={"phone": "13900000000"})
    assert challenge.status_code == 200, challenge.text
    response = client.post(
        "/api/v1/auth/login",
        json={
            "phone": "13900000000",
            "challenge_id": challenge.json()["data"]["challenge_id"],
            "code": sent[0],
        },
    )
    assert response.status_code == 200, response.text
    assert response.json()["data"]["user"]["id"] == "admin-demo"
    return {"Authorization": "Bearer " + response.json()["data"]["access_token"]}
