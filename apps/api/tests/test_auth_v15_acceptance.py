"""Black-box boundary checks. Only isolated test DB uses explicitly configured codes."""

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import func, select

from app.auth_models import AuthAudit, AuthState, LoginWhitelist
from app.core.config import get_settings
from app.core.database import SessionLocal
from app.models import User

BASE = "/api/v1"
PHONE = "13700000019"
CODE = "012349"


def configured(client, admin_headers, phone=PHONE):
    path = BASE + "/admin/auth/test-login-config"
    cfg = client.get(path, headers=admin_headers).json()["data"]
    updated = client.patch(
        path,
        headers=admin_headers,
        json={
            "enabled": True,
            "default_code": CODE,
            "expected_version": cfg["version"],
            "reason": "隔离测试验证",
        },
    )
    assert updated.status_code == 200, updated.text
    assert CODE not in updated.text
    wl = client.post(
        BASE + "/admin/auth/login-whitelist",
        headers=admin_headers,
        json={
            "phone": phone,
            "expires_at": (datetime.now(UTC) + timedelta(hours=1)).isoformat(),
            "owner": "测试",
            "purpose": "隔离数据库验证",
            "authorized": True,
        },
    )
    assert wl.status_code == 200, wl.text
    return updated.json()["data"], wl.json()["data"]


def challenge(client, phone=PHONE, purpose="login", headers=None):
    return client.post(
        BASE + "/auth/sms/challenges", headers=headers, json={"phone": phone, "purpose": purpose}
    )


def login(client, item, code=CODE, phone=PHONE):
    return client.post(
        BASE + "/auth/login",
        json={
            "method": "phone",
            "phone": phone,
            "challenge_id": item["challenge_id"],
            "code": code,
        },
    )


def test_legacy_fixed_code_and_client_identity_are_not_login_credentials(client):
    for method in ("phone", "wechat", "weibo"):
        response = client.post(
            BASE + "/auth/login",
            json={
                "method": method,
                "phone": "13900000000",
                "code": "666666",
                "oauth_code": "client-uid",
            },
        )
        assert 400 <= response.status_code < 500
        assert "access_token" not in response.text


def test_app_admin_audiences_are_mutually_exclusive(client, auth_headers, admin_headers):
    assert client.get(BASE + "/admin/auth/meta", headers=auth_headers).status_code == 401
    assert client.get(BASE + "/me/profile", headers=admin_headers).status_code == 401
    assert client.get(BASE + "/admin/auth/meta", headers=admin_headers).status_code == 200
    assert client.get(BASE + "/me/profile", headers=auth_headers).status_code == 200


def test_whitelist_only_creates_config_then_verified_login_creates_opaque_user(
    client, admin_headers
):
    with SessionLocal() as db:
        before = db.scalar(select(func.count()).select_from(User))
    configured(client, admin_headers)
    with SessionLocal() as db:
        assert db.scalar(select(func.count()).select_from(User)) == before
    sent = challenge(client)
    assert sent.status_code == 200
    assert sent.json()["data"]["delivery_mode"] == "test_code"
    assert CODE not in sent.text
    response = login(client, sent.json()["data"])
    assert response.status_code == 200, response.text
    user = response.json()["data"]["user"]
    assert PHONE not in user["id"]
    assert user["role"] == "user"
    assert login(client, sent.json()["data"]).status_code >= 400
    with SessionLocal() as db:
        assert db.scalar(select(func.count()).select_from(User)) == before + 1


@pytest.mark.parametrize(
    "operation", ["rotate", "disable_config", "disable_record", "expire_record"]
)
def test_pending_fixed_challenge_obeys_current_config(client, admin_headers, operation):
    cfg, wl = configured(client, admin_headers)
    item = challenge(client).json()["data"]
    if operation in {"rotate", "disable_config"}:
        payload = {
            "enabled": operation == "rotate",
            "expected_version": cfg["version"],
            "reason": "配置变更验证",
        }
        if operation == "rotate":
            payload["default_code"] = "910234"
        result = client.patch(
            BASE + "/admin/auth/test-login-config", headers=admin_headers, json=payload
        )
        assert result.status_code == 200
    elif operation == "disable_record":
        result = client.patch(
            BASE + "/admin/auth/login-whitelist/" + wl["id"],
            headers=admin_headers,
            json={"enabled": False, "expected_version": wl["version"], "reason": "停用测试"},
        )
        assert result.status_code == 200
    else:
        with SessionLocal() as db:
            db.get(LoginWhitelist, wl["id"]).expires_at = datetime.now(UTC) - timedelta(seconds=1)
            db.commit()
    response = login(client, item)
    assert response.status_code >= 400
    assert "access_token" not in response.text


def test_config_version_conflict_and_secrets_never_echo_or_audit(client, admin_headers):
    cfg, _ = configured(client, admin_headers)
    path = BASE + "/admin/auth/test-login-config"
    result = client.patch(
        path,
        headers=admin_headers,
        json={
            "enabled": True,
            "default_code": "765430",
            "expected_version": cfg["version"] - 1,
            "reason": "旧版本测试",
        },
    )
    assert result.status_code == 409
    public = client.get(path, headers=admin_headers)
    assert CODE not in public.text and "code_hash" not in public.text
    with SessionLocal() as db:
        records = [str(row.data) for row in db.scalars(select(AuthAudit))]
        assert all(CODE not in value and "765430" not in value for value in records)


def test_five_wrong_attempts_exhaust_challenge(client, admin_headers):
    configured(client, admin_headers)
    item = challenge(client).json()["data"]
    for _ in range(5):
        assert login(client, item, code="111111").status_code >= 400
    assert login(client, item).status_code >= 400


def test_login_challenge_cannot_authorize_sensitive_ticket(client, admin_headers):
    configured(client, admin_headers)
    item = challenge(client).json()["data"]
    result = client.post(
        BASE + "/auth/verification-tickets",
        json={"challenge_id": item["challenge_id"], "code": CODE},
    )
    assert result.status_code >= 400
    assert "verification_ticket" not in result.json().get("data", {})


def test_sensitive_operation_never_uses_fixed_code(client, auth_headers, monkeypatch):
    from app.modules.auth import providers

    monkeypatch.setattr(providers, "sms_available", lambda: False)
    monkeypatch.setattr(get_settings(), "sms_enabled", False)
    # Fixture's first login challenge is recent; expire only the rate-limit window.
    from app.auth_models import VerificationChallenge

    with SessionLocal() as db:
        for row in db.scalars(select(VerificationChallenge)):
            row.created_at = datetime.now(UTC) - timedelta(minutes=2)
        db.commit()
    result = challenge(client, "13800000000", "bind_identity", auth_headers)
    assert result.status_code == 503
    assert result.json()["error_code"] == "SMS_PROVIDER_NOT_CONFIGURED"


def test_banned_phone_not_disclosed_until_valid_verification(client, admin_headers):
    configured(client, admin_headers)
    with SessionLocal() as db:
        db.add(User(id="acceptance-banned", phone=PHONE, display_name="测试", is_active=False))
        db.add(
            AuthState(
                id="user:acceptance-banned",
                kind="account",
                data={
                    "public_message": "请联系客服核查",
                    "internal_reason": "sensitive-internal-reason",
                },
            )
        )
        db.commit()
    sent = challenge(client)
    assert sent.status_code == 200
    assert "BANNED" not in sent.text
    blocked = login(client, sent.json()["data"])
    assert blocked.status_code == 403
    assert blocked.json()["error_code"] == "ACCOUNT_BANNED"
    assert "sensitive-internal-reason" not in blocked.text
    assert "access_token" not in blocked.text


def test_production_cannot_enable_fixed_code(client, admin_headers, monkeypatch):
    monkeypatch.setattr(get_settings(), "environment", "production")
    path = BASE + "/admin/auth/test-login-config"
    cfg = client.get(path, headers=admin_headers).json()["data"]
    response = client.patch(
        path,
        headers=admin_headers,
        json={
            "enabled": True,
            "default_code": CODE,
            "expected_version": cfg["version"],
            "reason": "生产隔离测试",
        },
    )
    assert response.status_code == 403
    assert CODE not in response.text
