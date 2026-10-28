"""Isolated auth extensions. All provider responses are explicit test fixtures."""

import json
from datetime import timedelta

import httpx
import pytest
from sqlalchemy import select

from app.auth_models import AuthAudit, AuthSession, AuthState, TrustedIdentity
from app.common.response import DomainError
from app.core.config import get_settings
from app.core.database import SessionLocal
from app.core.security import check_secret, token_claims
from app.models import User
from app.modules.auth import providers
from app.modules.auth import service as s

BASE = "/api/v1"
PASSWORD = "NewPassword123"


def data(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def register(client, monkeypatch, phone="13612345670"):
    codes = []
    monkeypatch.setattr(
        providers, "send_sms", lambda number, code: codes.append(code) or "accepted"
    )
    challenge = data(client.post(BASE + "/auth/sms/challenges", json={"phone": phone}))
    return data(
        client.post(
            BASE + "/auth/login",
            json={
                "phone": phone,
                "challenge_id": challenge["challenge_id"],
                "code": codes[-1],
            },
        )
    )


def test_new_registration_requires_persisted_password_then_onboarding(client, monkeypatch):
    registered = register(client, monkeypatch)
    assert registered["is_new_user"] and registered["password_setup_required"]
    headers = {"Authorization": "Bearer " + registered["access_token"]}
    # A fresh request/session restore must see the persisted requirement.
    assert data(client.get(BASE + "/me/profile", headers=headers))["password_setup_required"]
    assert data(client.get(BASE + "/account/identities", headers=headers))[
        "password_setup_required"
    ]
    assert client.post(BASE + "/account/onboarding/complete", headers=headers).status_code == 409
    for invalid in ("12345678", "abcdefgh", "Pass123", "Pass word123"):
        assert (
            client.post(
                BASE + "/account/password", headers=headers, json={"password": invalid}
            ).status_code
            == 400
        )
    setup_headers = {**headers, "Idempotency-Key": "first-password"}
    body = {"password": PASSWORD}
    saved = data(client.post(BASE + "/account/password", headers=setup_headers, json=body))
    assert saved == {"password_setup_required": False, "onboarding_completed": False}
    assert data(client.post(BASE + "/account/password", headers=setup_headers, json=body)) == saved
    assert client.post(BASE + "/account/password", headers=headers, json=body).status_code == 409
    with SessionLocal() as db:
        hashed = db.get(AuthState, "user-password:" + registered["user"]["id"]).data[
            "password_hash"
        ]
        assert hashed != PASSWORD and check_secret(PASSWORD, hashed)
        assert PASSWORD not in json.dumps([r.data for r in db.scalars(select(AuthState))])
        assert PASSWORD not in json.dumps([r.data for r in db.scalars(select(AuthAudit))])
    restored = data(
        client.post(BASE + "/auth/refresh", json={"refresh_token": registered["refresh_token"]})
    )
    assert not restored["password_setup_required"] and not restored["onboarding_completed"]
    headers = {"Authorization": "Bearer " + restored["access_token"]}
    data(client.post(BASE + "/account/onboarding/complete", headers=headers))
    logged = data(
        client.post(
            BASE + "/auth/login",
            json={
                "method": "password",
                "phone": "13612345670",
                "password": PASSWORD,
            },
            headers={"Idempotency-Key": "password-retry"},
        )
    )
    repeated = data(
        client.post(
            BASE + "/auth/login",
            json={
                "method": "password",
                "phone": "13612345670",
                "password": PASSWORD,
            },
            headers={"Idempotency-Key": "password-retry"},
        )
    )
    assert logged["access_token"] == repeated["access_token"]
    assert logged["user"]["id"] == registered["user"]["id"]
    assert logged["onboarding_completed"] and not logged["password_setup_required"]
    assert (
        client.get(
            BASE + "/admin/auth/meta",
            headers={
                "Authorization": "Bearer " + logged["access_token"],
            },
        ).status_code
        == 401
    )


def test_legacy_accounts_are_not_forced_and_password_login_does_not_register(client, auth_headers):
    current = data(client.get(BASE + "/me/profile", headers=auth_headers))
    assert current["onboarding_completed"] and not current["password_setup_required"]
    missing = client.post(
        BASE + "/auth/login",
        json={
            "method": "password",
            "phone": "13612345670",
            "password": PASSWORD,
        },
    )
    unset = client.post(
        BASE + "/auth/login",
        json={
            "method": "password",
            "phone": "13800000000",
            "password": PASSWORD,
        },
    )
    assert missing.status_code == unset.status_code == 401
    assert missing.json()["code"] == unset.json()["code"]
    with SessionLocal() as db:
        assert not db.scalar(select(User).where(User.phone == "13612345670"))


def test_password_attempts_limited_and_stale_setup_cannot_overwrite(client, auth_headers):
    for _ in range(10):
        assert (
            client.post(
                BASE + "/auth/login",
                json={
                    "method": "password",
                    "phone": "13800000000",
                    "password": "bad",
                },
            ).status_code
            == 401
        )
    assert (
        client.post(
            BASE + "/auth/login",
            json={
                "method": "password",
                "phone": "13800000000",
                "password": "bad",
            },
        ).status_code
        == 429
    )
    sid = token_claims(auth_headers["Authorization"].split()[1])["sid"]
    with SessionLocal() as db:
        db.get(AuthSession, sid).created_at = s.now() - timedelta(minutes=16)
        s.change_state(
            db.get(AuthState, "session-auth:" + sid),
            authenticated_at=(s.now() - timedelta(minutes=16)).isoformat(),
        )
        db.commit()
    assert (
        client.post(
            BASE + "/account/password", headers=auth_headers, json={"password": PASSWORD}
        ).status_code
        == 403
    )


def test_refresh_cannot_bypass_recent_authentication_for_password_setup(client, monkeypatch):
    registered = register(client, monkeypatch)
    sid = token_claims(registered["access_token"])["sid"]
    with SessionLocal() as db:
        s.change_state(
            db.get(AuthState, "session-auth:" + sid),
            authenticated_at=(s.now() - timedelta(minutes=16)).isoformat(),
        )
        db.commit()
    refreshed = data(
        client.post(BASE + "/auth/refresh", json={"refresh_token": registered["refresh_token"]})
    )
    assert refreshed["password_setup_required"]
    assert (
        client.post(
            BASE + "/account/password",
            headers={"Authorization": "Bearer " + refreshed["access_token"]},
            json={"password": PASSWORD},
        ).status_code
        == 403
    )


def test_qq_bound_account_login_uses_one_time_verified_transaction(client, monkeypatch):
    enable_qq(monkeypatch)
    with SessionLocal() as db:
        db.add(
            TrustedIdentity(
                user_id="current-user",
                provider="qq",
                app_scope="12345",
                subject="trusted-qq-openid",
                display_name="QQ 昵称",
            )
        )
        db.commit()
    monkeypatch.setattr(
        providers.httpx,
        "request",
        lambda method, url, **kwargs: httpx.Response(
            200,
            json={"client_id": "12345", "openid": "trusted-qq-openid"}
            if url.endswith("/me")
            else {"ret": 0, "nickname": "可信 QQ 昵称"},
        ),
    )
    transaction = data(
        client.post(BASE + "/auth/oauth/transactions", json={"provider": "qq", "intent": "login"})
    )
    body = {
        "transaction_id": transaction["transaction_id"],
        "state": transaction["state"],
        "credential_type": "access_token",
        "credential": "private-qq-token",
    }
    completed = data(client.post(BASE + "/auth/oauth/complete", json=body))
    assert completed["user"]["id"] == "current-user" and completed["status"] == "LOGIN_SUCCESS"
    assert not completed["password_setup_required"]
    assert client.post(BASE + "/auth/oauth/complete", json=body).status_code == 400
    assert "private-qq-token" not in json.dumps(completed)


def enable_qq(monkeypatch):
    settings = get_settings()
    for key, value in {
        "oauth_native_verified": True,
        "qq_enabled": True,
        "qq_app_id": "12345",
        "qq_universal_link": "https://test.example/qq/",
    }.items():
        monkeypatch.setattr(settings, key, value)


def test_qq_server_verifies_app_scope_and_profile_without_exposing_tokens(monkeypatch):
    enable_qq(monkeypatch)
    calls = []

    def request(method, url, **kwargs):
        calls.append((url, kwargs))
        assert not kwargs["follow_redirects"]
        return httpx.Response(
            200,
            json=(
                {"client_id": "12345", "openid": "trusted-qq-openid"}
                if url.endswith("/me")
                else {"ret": 0, "nickname": "QQ 昵称"}
            ),
        )

    monkeypatch.setattr(providers.httpx, "request", request)
    identity = providers.verify_oauth("qq", "access_token", "private-qq-token")
    assert identity["subject"] == "trusted-qq-openid" and identity["app_scope"] == "12345"
    assert identity["display_name"] == "QQ 昵称" and identity["authorization_status"] == "unknown"
    assert "private-qq-token" not in json.dumps(identity)
    assert calls[0][1]["params"]["fmt"] == "json"
    with pytest.raises(DomainError):
        providers.verify_oauth("qq", "openid", "client-supplied-id")
    monkeypatch.setattr(get_settings(), "oauth_native_verified", False)
    with pytest.raises(DomainError):
        providers.verify_oauth("qq", "access_token", "private-qq-token")


@pytest.mark.parametrize(
    "identity,profile",
    [
        ({"client_id": "foreign-app", "openid": "subject"}, {"ret": 0}),
        ({"client_id": "12345"}, {"ret": 0}),
        ({"client_id": "12345", "openid": "subject"}, {"ret": 1002}),
    ],
)
def test_qq_rejects_foreign_or_invalid_credentials(monkeypatch, identity, profile):
    enable_qq(monkeypatch)
    monkeypatch.setattr(
        providers.httpx,
        "request",
        lambda method, url, **kw: httpx.Response(
            200, json=identity if url.endswith("/me") else profile
        ),
    )
    with pytest.raises(DomainError):
        providers.verify_oauth("qq", "access_token", "private-token")


def test_qq_is_visible_in_admin_binding_details_and_filter(client, auth_headers, admin_headers):
    with SessionLocal() as db:
        db.add(
            TrustedIdentity(
                user_id="current-user",
                provider="qq",
                app_scope="12345",
                subject="trusted-qq-identity",
                display_name="QQ 昵称",
                authorization_status="unknown",
            )
        )
        db.commit()
    identities = data(client.get(BASE + "/account/identities", headers=auth_headers))["identities"]
    assert next(row for row in identities if row["provider"] == "qq")["bound"]
    listed = data(client.get(BASE + "/admin/auth/users?qq=bound", headers=admin_headers))
    assert [r["id"] for r in listed["items"]] == ["current-user"]
    detail = data(client.get(BASE + "/admin/auth/users/current-user", headers=admin_headers))
    qq = next(row for row in detail["identities"] if row["provider"] == "qq")
    assert qq["display_name"] == "QQ 昵称" and qq["subject_masked"] != "trusted-qq-identity"
    assert client.get(BASE + "/admin/auth/users?qq=bound", headers=auth_headers).status_code == 401
