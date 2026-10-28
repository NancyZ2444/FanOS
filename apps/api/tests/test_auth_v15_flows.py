"""Security integration tests: isolated DB, provider responses are explicit mocks."""

from datetime import timedelta

from app.auth_models import VerificationChallenge
from app.core.database import SessionLocal
from app.models import User
from app.modules.auth import providers
from app.modules.auth import service as s

PREFIX = "/api/v1"


def data(response, status=200):
    assert response.status_code == status, response.text
    return response.json()["data"]


def sms_ticket(client, monkeypatch, headers, phone, purpose, sent):
    def deliver(number, code):
        sent.append((number, code))
        return "accepted"

    monkeypatch.setattr(providers, "send_sms", deliver)
    # Isolated fixture simulates passage of cooldown, never production bypass.
    with SessionLocal() as db:
        from sqlalchemy import select

        for row in db.scalars(
            select(VerificationChallenge).where(VerificationChallenge.phone == phone)
        ):
            row.created_at = s.now() - timedelta(minutes=2)
        db.commit()
    c = data(
        client.post(
            PREFIX + "/auth/sms/challenges",
            headers=headers,
            json={"phone": phone, "purpose": purpose},
        )
    )
    assert c["delivery_mode"] == "sms"
    return data(
        client.post(
            PREFIX + "/auth/verification-tickets",
            headers=headers,
            json={"challenge_id": c["challenge_id"], "code": sent[-1][1]},
        )
    )["verification_ticket"]


def test_real_sms_sensitive_ticket_and_atomic_phone_change(client, auth_headers, monkeypatch):
    sent = []
    old = sms_ticket(client, monkeypatch, auth_headers, "13800000000", "change_phone_old", sent)
    new = sms_ticket(client, monkeypatch, auth_headers, "13612345678", "change_phone_new", sent)
    result = data(
        client.post(
            PREFIX + "/account/change-phone",
            headers={**auth_headers, "Idempotency-Key": "phone-change-retry"},
            json={"old_verification_ticket": old, "new_verification_ticket": new},
        )
    )
    assert result["user"]["id"] == "current-user"
    repeated = data(
        client.post(
            PREFIX + "/account/change-phone",
            headers={**auth_headers, "Idempotency-Key": "phone-change-retry"},
            json={"old_verification_ticket": old, "new_verification_ticket": new},
        )
    )
    assert repeated["access_token"] == result["access_token"]
    assert client.get(PREFIX + "/me/profile", headers=auth_headers).status_code == 401
    new_headers = {"Authorization": "Bearer " + result["access_token"]}
    assert client.get(PREFIX + "/me/profile", headers=new_headers).status_code == 200
    assert (
        client.post(
            PREFIX + "/account/change-phone",
            headers={**auth_headers, "Idempotency-Key": "different-key"},
            json={"old_verification_ticket": old, "new_verification_ticket": new},
        ).status_code
        == 401
    )
    with SessionLocal() as db:
        assert db.get(User, "current-user").phone == "13612345678"
        assert not s.whitelist(db, "13800000000").enabled


def test_oauth_identity_comes_from_adapter_and_preserves_assets(client, auth_headers, monkeypatch):
    monkeypatch.setattr(providers, "oauth_parameters", lambda provider: {"app_id": "test-scope"})
    monkeypatch.setattr(
        providers,
        "verify_oauth",
        lambda provider, kind, credential: {
            "app_scope": "test-scope",
            "subject": "verified-subject",
            "display_name": "真实平台昵称",
            "profile_url": "https://weibo.com/u/1234567890",
            "authorization_status": "valid",
        },
    )
    sent = []
    ticket = sms_ticket(client, monkeypatch, auth_headers, "13800000000", "bind_identity", sent)
    transaction = data(
        client.post(
            PREFIX + "/auth/oauth/transactions",
            headers=auth_headers,
            json={"provider": "weibo", "intent": "bind", "verification_ticket": ticket},
        )
    )
    completed = data(
        client.post(
            PREFIX + "/auth/oauth/complete",
            headers=auth_headers,
            json={
                **{k: transaction[k] for k in ("transaction_id", "state")},
                "credential_type": "code",
                "credential": "single-use-provider-code",
            },
        )
    )
    assert completed["status"] == "BOUND"
    profile = data(client.get(PREFIX + "/me/profile", headers=auth_headers))
    assert profile["weibo_name"] is None
    assert profile["weibo_profile_url"] is None
    assert profile["weibo_url"] is None
    data(client.patch(PREFIX + "/me/profile", headers=auth_headers, json={"weibo_visible": True}))
    profile = data(client.get(PREFIX + "/me/profile", headers=auth_headers))
    assert profile["weibo_name"] == "真实平台昵称"
    assert profile["weibo_profile_url"] == "https://weibo.com/u/1234567890"
    assert profile["weibo_url"] == profile["weibo_profile_url"]
    tx = data(
        client.post(
            PREFIX + "/auth/oauth/transactions", json={"provider": "weibo", "intent": "login"}
        )
    )
    logged = data(
        client.post(
            PREFIX + "/auth/oauth/complete",
            json={
                **{k: tx[k] for k in ("transaction_id", "state")},
                "credential_type": "code",
                "credential": "other-code",
            },
        )
    )
    assert logged["status"] == "LOGIN_SUCCESS"
    assert logged["user"]["id"] == "current-user"
    assert logged["user"]["role"] == "user"
    assert (
        client.post(
            PREFIX + "/auth/oauth/complete",
            json={
                **{k: tx[k] for k in ("transaction_id", "state")},
                "credential_type": "code",
                "credential": "replay",
            },
        ).status_code
        == 400
    )


def test_admin_separation_and_credential_revoke(client, admin_headers, auth_headers):
    old_users = data(client.get(PREFIX + "/admin/auth/users", headers=admin_headers))["total"]
    admin = data(
        client.post(
            PREFIX + "/admin/console/admins",
            headers=admin_headers,
            json={
                "account": "separate-operator",
                "name": "Operator",
                "role": "operation_admin",
                "password": "Independent-Password-123",
                "reason": "测试后台独立身份",
            },
        )
    )
    assert (
        data(client.get(PREFIX + "/admin/auth/users", headers=admin_headers))["total"] == old_users
    )
    session = data(
        client.post(
            PREFIX + "/admin/auth/login",
            json={"account": "separate-operator", "password": "Independent-Password-123"},
        )
    )
    headers = {"Authorization": "Bearer " + session["access_token"]}
    assert client.get(PREFIX + "/me/profile", headers=headers).status_code == 401
    assert client.get(PREFIX + "/admin/auth/test-login-config", headers=headers).status_code == 403
    data(
        client.patch(
            PREFIX + "/admin/console/admins/" + admin["id"],
            headers=admin_headers,
            json={
                "role": "operation_admin",
                "is_active": False,
                "reason": "测试停用",
                "expected_version": admin["version"],
            },
        )
    )
    assert client.get(PREFIX + "/admin/console/me", headers=headers).status_code == 403
    assert client.get(PREFIX + "/me/profile", headers=auth_headers).status_code == 200


def test_unverified_legacy_weibo_never_fabricated(client, auth_headers):
    with SessionLocal() as db:
        user = db.get(User, "current-user")
        user.weibo_visible = True
        db.commit()
    profile = data(client.get(PREFIX + "/me/profile", headers=auth_headers))
    assert profile["weibo_name"] is None
    assert profile["weibo_profile_url"] is None
    assert profile["weibo_url"] is None
    assert (
        client.patch(
            PREFIX + "/me/profile", headers=auth_headers, json={"weibo_visible": True}
        ).status_code
        == 409
    )


def test_trusted_weibo_profile_link_respects_visibility_missing_url_and_unbind(
    client, auth_headers, second_app_headers, monkeypatch
):
    from app.auth_models import TrustedIdentity

    # A trusted provider fixture, never a user-supplied URL or a legacy flag.
    trusted_url = "https://weibo.com/u/1234567890"
    with SessionLocal() as db:
        identity = TrustedIdentity(
            user_id="current-user",
            provider="weibo",
            app_scope="verified-app",
            subject="1234567890",
            display_name="可信微博昵称",
            profile_url=trusted_url,
        )
        db.add(identity)
        db.get(User, "current-user").weibo_visible = False
        db.commit()
        identity_id = identity.id
        identity_version = identity.version

    def assert_urls(expected):
        for path, headers in (
            ("/me/profile", auth_headers),
            ("/users/current-user", second_app_headers),
        ):
            profile = data(client.get(PREFIX + path, headers=headers))
            assert profile["weibo_profile_url"] == expected
            assert profile["weibo_url"] == expected

    assert_urls(None)
    data(client.patch(PREFIX + "/me/profile", headers=auth_headers, json={"weibo_visible": True}))
    assert_urls(trusted_url)
    with SessionLocal() as db:
        db.get(TrustedIdentity, identity_id).profile_url = None
        db.commit()
    assert_urls(None)
    with SessionLocal() as db:
        db.get(TrustedIdentity, identity_id).profile_url = trusted_url
        db.commit()
    sent = []
    ticket = sms_ticket(client, monkeypatch, auth_headers, "13800000000", "unbind_identity", sent)
    result = data(
        client.post(
            PREFIX + "/account/identities/weibo/unbind",
            headers=auth_headers,
            json={"verification_ticket": ticket, "expected_version": identity_version},
        )
    )
    auth_headers = {"Authorization": "Bearer " + result["access_token"]}
    assert_urls(None)


def test_sms_and_refresh_retry_same_key_are_not_replayed(client, monkeypatch):
    sent = []
    monkeypatch.setattr(providers, "send_sms", lambda phone, code: sent.append(code) or "accepted")
    headers = {"Idempotency-Key": "challenge-retry"}
    body = {"phone": "13623456789", "purpose": "login"}
    first = data(client.post(PREFIX + "/auth/sms/challenges", headers=headers, json=body))
    second = data(client.post(PREFIX + "/auth/sms/challenges", headers=headers, json=body))
    assert first == second
    assert len(sent) == 1
    logged = data(
        client.post(
            PREFIX + "/auth/login",
            headers={"Idempotency-Key": "login-retry"},
            json={
                "method": "phone",
                "phone": body["phone"],
                "challenge_id": first["challenge_id"],
                "code": sent[-1],
            },
        )
    )
    refresh_body = {"refresh_token": logged["refresh_token"]}
    refreshed = data(
        client.post(
            PREFIX + "/auth/refresh",
            headers={"Idempotency-Key": "refresh-retry"},
            json=refresh_body,
        )
    )
    retried = data(
        client.post(
            PREFIX + "/auth/refresh",
            headers={"Idempotency-Key": "refresh-retry"},
            json=refresh_body,
        )
    )
    assert refreshed["refresh_token"] == retried["refresh_token"]
    assert (
        client.post(
            PREFIX + "/auth/refresh", headers={"Idempotency-Key": "different"}, json=refresh_body
        ).status_code
        == 401
    )


def test_first_oauth_phone_confirmation_can_recover_response(client, monkeypatch):
    sent = []
    monkeypatch.setattr(providers, "send_sms", lambda phone, code: sent.append(code) or "accepted")
    monkeypatch.setattr(providers, "oauth_parameters", lambda provider: {"app_id": "test"})
    monkeypatch.setattr(
        providers,
        "verify_oauth",
        lambda *args: {
            "app_scope": "test",
            "subject": "unregistered",
            "display_name": "授权昵称",
            "authorization_status": "valid",
        },
    )
    transaction = data(
        client.post(
            PREFIX + "/auth/oauth/transactions",
            json={"provider": "wechat", "intent": "login"},
            headers={"Idempotency-Key": "transaction"},
        )
    )
    assert transaction == data(
        client.post(
            PREFIX + "/auth/oauth/transactions",
            json={"provider": "wechat", "intent": "login"},
            headers={"Idempotency-Key": "transaction"},
        )
    )
    complete = {k: transaction[k] for k in ("transaction_id", "state")}
    complete.update(credential_type="code", credential="one-time-code")
    pending = data(
        client.post(
            PREFIX + "/auth/oauth/complete",
            json=complete,
            headers={"Idempotency-Key": "oauth-complete"},
        )
    )
    assert pending == data(
        client.post(
            PREFIX + "/auth/oauth/complete",
            json=complete,
            headers={"Idempotency-Key": "oauth-complete"},
        )
    )
    challenge = data(
        client.post(
            PREFIX + "/auth/sms/challenges",
            json={"phone": "13634567890", "purpose": "complete_phone"},
        )
    )
    proof_body = {"challenge_id": challenge["challenge_id"], "code": sent[-1]}
    proof = data(
        client.post(
            PREFIX + "/auth/verification-tickets",
            json=proof_body,
            headers={"Idempotency-Key": "ticket"},
        )
    )
    assert proof == data(
        client.post(
            PREFIX + "/auth/verification-tickets",
            json=proof_body,
            headers={"Idempotency-Key": "ticket"},
        )
    )
    bind_body = {
        "continuation_token": pending["continuation_token"],
        "verification_ticket": proof["verification_ticket"],
        "confirm_link": True,
    }
    logged = data(
        client.post(
            PREFIX + "/auth/oauth/complete-phone",
            json=bind_body,
            headers={"Idempotency-Key": "complete-phone"},
        )
    )
    retried = data(
        client.post(
            PREFIX + "/auth/oauth/complete-phone",
            json=bind_body,
            headers={"Idempotency-Key": "complete-phone"},
        )
    )
    assert logged["access_token"] == retried["access_token"]
    assert logged["is_new_user"] is True
    headers = {"Authorization": "Bearer " + logged["access_token"]}
    assert logged["user"]["onboarding_completed"] is False
    assert logged["password_setup_required"] is True
    assert (
        data(client.get(PREFIX + "/me/profile", headers=headers))["onboarding_completed"] is False
    )
    assert client.post(PREFIX + "/account/onboarding/complete", headers=headers).status_code == 409
    data(
        client.post(
            PREFIX + "/account/password", headers=headers, json={"password": "TestPassword123"}
        )
    )
    data(client.post(PREFIX + "/account/onboarding/complete", headers=headers))
    assert data(client.get(PREFIX + "/me/profile", headers=headers))["onboarding_completed"] is True


def test_existing_user_keeps_onboarding_and_identity_authorization_expiry(client, auth_headers):
    from app.auth_models import TrustedIdentity

    assert (
        data(client.get(PREFIX + "/me/profile", headers=auth_headers))["onboarding_completed"]
        is True
    )
    with SessionLocal() as db:
        db.add(
            TrustedIdentity(
                user_id="current-user",
                provider="weibo",
                app_scope="scope",
                subject="verified",
                display_name="真实昵称",
                authorization_status="valid",
                authorization_expires_at=s.now() - timedelta(seconds=1),
            )
        )
        db.commit()
    identities = data(client.get(PREFIX + "/account/identities", headers=auth_headers))[
        "identities"
    ]
    assert (
        next(row for row in identities if row["provider"] == "weibo")["authorization_status"]
        == "expired"
    )


def test_concurrent_registration_recovers_one_account_and_session(client, monkeypatch):
    from concurrent.futures import ThreadPoolExecutor

    from sqlalchemy import func, select

    sent = []
    monkeypatch.setattr(providers, "send_sms", lambda phone, code: sent.append(code) or "accepted")
    phone = "13655556666"
    challenge = data(client.post(PREFIX + "/auth/sms/challenges", json={"phone": phone}))
    body = {"phone": phone, "challenge_id": challenge["challenge_id"], "code": sent[0]}

    def submit(_):
        return data(
            client.post(
                PREFIX + "/auth/login",
                json=body,
                headers={"Idempotency-Key": "concurrent-new-account"},
            )
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        first, second = list(pool.map(submit, range(2)))
    assert first["user"]["id"] == second["user"]["id"]
    assert first["access_token"] == second["access_token"]
    with SessionLocal() as db:
        assert db.scalar(select(func.count()).select_from(User).where(User.phone == phone)) == 1


def test_phoneless_legacy_identity_keeps_its_original_user_id(client, monkeypatch):
    from app.auth_models import TrustedIdentity

    sent = []
    monkeypatch.setattr(providers, "send_sms", lambda phone, code: sent.append(code) or "accepted")
    monkeypatch.setattr(providers, "oauth_parameters", lambda provider: {"app_id": "legacy"})
    monkeypatch.setattr(
        providers,
        "verify_oauth",
        lambda *args: {
            "app_scope": "legacy",
            "subject": "existing-subject",
            "display_name": "平台昵称",
            "authorization_status": "unknown",
        },
    )
    with SessionLocal() as db:
        db.add(User(id="legacy-no-phone", display_name="保留的昵称", phone=None))
        db.add(
            TrustedIdentity(
                user_id="legacy-no-phone",
                provider="wechat",
                app_scope="legacy",
                subject="existing-subject",
                display_name="平台昵称",
            )
        )
        db.commit()
    tx = data(
        client.post(
            PREFIX + "/auth/oauth/transactions", json={"provider": "wechat", "intent": "login"}
        )
    )
    pending = data(
        client.post(
            PREFIX + "/auth/oauth/complete",
            json={
                "transaction_id": tx["transaction_id"],
                "state": tx["state"],
                "credential_type": "code",
                "credential": "trusted-code",
            },
        )
    )
    assert pending["status"] == "PHONE_REQUIRED" and "access_token" not in pending
    challenge = data(
        client.post(
            PREFIX + "/auth/sms/challenges",
            json={
                "phone": "13688889999",
                "purpose": "complete_phone",
            },
        )
    )
    ticket = data(
        client.post(
            PREFIX + "/auth/verification-tickets",
            json={
                "challenge_id": challenge["challenge_id"],
                "code": sent[0],
            },
        )
    )
    body = {
        "continuation_token": pending["continuation_token"],
        "verification_ticket": ticket["verification_ticket"],
        "confirm_link": True,
    }
    preview = data(client.post(PREFIX + "/auth/oauth/preview-phone", json=body))
    assert preview["display_name"] == "保留的昵称" and preview["is_existing"]
    result = data(client.post(PREFIX + "/auth/oauth/complete-phone", json=body))
    assert result["user"]["id"] == "legacy-no-phone"
    assert result["is_new_user"] is False
