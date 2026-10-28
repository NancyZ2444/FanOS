"""Admin password resets run against the isolated test database only."""

import json

import pytest
from sqlalchemy import select

from app.auth_models import AuthAudit, AuthState
from app.core.database import SessionLocal
from app.core.security import check_secret
from app.models import User, UserCollectionItem, UserWishlistItem
from app.modules.admin.permissions import KEY

BASE = "/api/v1"
PASSWORD = "Reset-Password789!"


def data(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def target(client, admin_headers, auth_headers):
    user_id = data(client.get(BASE + "/me/profile", headers=auth_headers))["id"]
    user = data(client.get(BASE + "/admin/auth/users/" + user_id, headers=admin_headers))
    return user_id, user["version"]


def reset(client, headers, user_id, version, **values):
    return client.post(
        BASE + "/admin/auth/users/" + user_id + "/password-reset",
        headers=headers,
        json={
            "new_password": PASSWORD,
            "reason": "已核验账户所有者，恢复密码登录",
            "confirmed": True,
            "expected_version": version,
            **values,
        },
    )


def password_login(client, password):
    return client.post(
        BASE + "/auth/login",
        json={"method": "password", "phone": "13800000000", "password": password},
    )


def asset_snapshot(db, user_id):
    return {
        model.__tablename__: [
            {column.name: getattr(row, column.name) for column in model.__table__.columns}
            for row in db.scalars(select(model).where(model.user_id == user_id))
        ]
        for model in (UserCollectionItem, UserWishlistItem)
    }


def test_reset_preserves_user_assets_and_revokes_only_target_app_sessions(
    client, admin_headers, auth_headers, second_app_headers
):
    user_id, version = target(client, admin_headers, auth_headers)
    first = data(reset(client, admin_headers, user_id, version, new_password="Previous-Pass123"))
    old_login = data(password_login(client, "Previous-Pass123"))
    old_headers = {"Authorization": "Bearer " + old_login["access_token"]}
    with SessionLocal() as db:
        before = asset_snapshot(db, user_id)
        user = db.get(User, user_id)
        profile = (user.display_name, user.phone, user.is_active)
        old_hash = db.get(AuthState, "user-password:" + user_id).data["password_hash"]
    version = data(client.get(BASE + "/admin/auth/users/" + user_id, headers=admin_headers))[
        "version"
    ]
    response = reset(client, admin_headers, user_id, version)
    saved = data(response)
    assert saved == {"user_id": user_id, "version": version + 1, "sessions_revoked": True}
    assert PASSWORD not in response.text and "password_hash" not in response.text
    assert saved["version"] > first["version"]
    assert client.get(BASE + "/me/profile", headers=auth_headers).status_code == 401
    assert client.get(BASE + "/me/profile", headers=old_headers).status_code == 401
    assert (
        client.post(
            BASE + "/auth/refresh", json={"refresh_token": old_login["refresh_token"]}
        ).status_code
        == 401
    )
    assert client.get(BASE + "/me/profile", headers=second_app_headers).status_code == 200
    assert client.get(BASE + "/admin/auth/meta", headers=admin_headers).status_code == 200
    assert password_login(client, "Previous-Pass123").status_code == 401
    logged = data(password_login(client, PASSWORD))
    assert logged["user"]["id"] == user_id and not logged["password_setup_required"]
    with SessionLocal() as db:
        assert asset_snapshot(db, user_id) == before
        user = db.get(User, user_id)
        assert (user.display_name, user.phone, user.is_active) == profile
        credential = db.get(AuthState, "user-password:" + user_id).data
        assert check_secret(PASSWORD, credential["password_hash"])
        assert credential["password_hash"] != old_hash
        audits = list(
            db.scalars(select(AuthAudit).where(AuthAudit.action == "user.password_reset"))
        )
        assert len(audits) == 2
        serialized = json.dumps([r.data for r in audits])
        assert PASSWORD not in serialized and credential["password_hash"] not in serialized
        assert all(r.actor_id == "admin-principal-test" and r.user_id == user_id for r in audits)
    detail = client.get(BASE + "/admin/auth/users/" + user_id, headers=admin_headers)
    listing = client.get(BASE + "/admin/auth/users", headers=admin_headers)
    assert PASSWORD not in detail.text + listing.text
    assert "password_hash" not in detail.text + listing.text


@pytest.mark.parametrize(
    "changes",
    [
        {"confirmed": False},
        {"confirmed": "true"},
        {"reason": "   "},
        {"reason": "密码为 " + PASSWORD},
        {"new_password": "12345678"},
        {"new_password": "abcdefgh"},
        {"new_password": "Abc123"},
        {"new_password": "Abc 12345"},
        {"new_password": "a1" * 33},
    ],
)
def test_reset_requires_confirmation_reason_and_strong_password(
    client, admin_headers, auth_headers, changes
):
    user_id, version = target(client, admin_headers, auth_headers)
    response = reset(client, admin_headers, user_id, version, **changes)
    assert response.status_code in {400, 422}
    assert PASSWORD not in response.text
    assert client.get(BASE + "/me/profile", headers=auth_headers).status_code == 200
    with SessionLocal() as db:
        assert db.get(AuthState, "user-password:" + user_id) is None
        assert not db.scalar(select(AuthAudit).where(AuthAudit.action == "user.password_reset"))


def test_reset_version_conflict_does_not_change_password_or_revoke_new_session(
    client, admin_headers, auth_headers
):
    user_id, version = target(client, admin_headers, auth_headers)
    data(reset(client, admin_headers, user_id, version))
    logged = data(password_login(client, PASSWORD))
    stale = reset(client, admin_headers, user_id, version, new_password="Overwritten123")
    assert stale.status_code == 409
    headers = {"Authorization": "Bearer " + logged["access_token"]}
    assert client.get(BASE + "/me/profile", headers=headers).status_code == 200
    with SessionLocal() as db:
        assert check_secret(
            PASSWORD, db.get(AuthState, "user-password:" + user_id).data["password_hash"]
        )


def test_password_reset_has_dedicated_delegatable_permission(
    client, admin_headers, auth_headers, admin_actor_headers
):
    user_id, version = target(client, admin_headers, auth_headers)
    operator = admin_actor_headers("operation_admin", "password-support")
    assert reset(client, auth_headers, user_id, version).status_code == 401
    assert reset(client, operator, user_id, version).status_code == 403
    with SessionLocal() as db:
        db.add(
            AuthState(
                id=KEY, kind=KEY, data={"operation_admin": ["auth.users.view", "auth.users.manage"]}
            )
        )
        db.commit()
    assert reset(client, operator, user_id, version).status_code == 403
    with SessionLocal() as db:
        row = db.get(AuthState, KEY)
        row.data = {"operation_admin": ["auth.users.view", "auth.users.password"]}
        db.commit()
    assert (
        "auth.users.password"
        in data(client.get(BASE + "/admin/auth/meta", headers=operator))["permissions"]
    )
    data(reset(client, operator, user_id, version))


def test_password_reset_keeps_banned_account_banned(client, admin_headers, auth_headers):
    user_id, version = target(client, admin_headers, auth_headers)
    with SessionLocal() as db:
        db.get(User, user_id).is_active = False
        db.commit()
    data(reset(client, admin_headers, user_id, version))
    assert password_login(client, PASSWORD).status_code == 401
    with SessionLocal() as db:
        assert not db.get(User, user_id).is_active
