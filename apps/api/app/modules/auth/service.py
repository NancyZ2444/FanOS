from __future__ import annotations

import re
import secrets
from contextvars import ContextVar
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, update

from app.auth_models import AuthAudit, AuthSession, AuthState, LoginWhitelist, VerificationChallenge
from app.common.response import DomainError
from app.core.config import get_settings
from app.core.security import (
    account_available,
    aware,
    check_secret,
    create_token,
    digest,
    resolve_session,
    secret_hash,
)
from app.models import User, new_id
from app.modules.auth import providers

SENSITIVE = {"bind_identity", "unbind_identity", "change_phone_old", "change_phone_new"}
PURPOSES = SENSITIVE | {"login", "complete_phone"}
audit_context = ContextVar("auth_audit_context", default=None)
_DUMMY_PASSWORD_HASH = secret_hash(secrets.token_urlsafe(32))


def now():
    return datetime.now(UTC)


def lock(db, allow_recovery=False):
    # Global short auth mutation lock also works across worker processes. All auth writes
    # use this lock; catalog/business reads do not. SQLite obtains its write lock here.
    db.execute(
        update(AuthState).where(AuthState.id == "auth-lock").values(version=AuthState.version)
    )
    db.expire_all()
    # Permissions/session status may have changed while this request waited for the lock.
    for actor in list(db.identity_map.values()):
        sid = getattr(actor, "_auth_session_id", None)
        if sid:
            session = db.get(AuthSession, sid)
            if (
                not session
                or (session.revoked and not allow_recovery)
                or aware(session.expires_at) <= now()
            ):
                raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)
            if isinstance(actor, User):
                account_available(db, actor)
            elif not actor.is_active:
                raise DomainError("ADMIN_UNAVAILABLE", "后台账号已停用", 403)


def state(db, key, kind="account"):
    row = db.get(AuthState, key)
    if row is None:
        row = AuthState(id=key, kind=kind, data={}, version=1)
        db.add(row)
        db.flush()
    return row


def change_state(row, **values):
    row.data = {**row.data, **values}
    row.version += 1


def audit(db, action, actor=None, user_id=None, **data):
    db.add(
        AuthAudit(
            action=action,
            actor_id=getattr(actor, "id", None),
            user_id=user_id,
            data={**(audit_context.get() or {}), **data},
        )
    )


def cached_result(db, scope, key, payload, user=None):
    import json

    if not key:
        return None
    row = db.get(AuthState, "result:" + digest(scope + ":" + key))
    if row is None:
        return None
    proof = digest(json.dumps(payload, sort_keys=True, default=str))
    if (
        row.data.get("proof") != proof
        or row.data.get("subject") != getattr(user, "id", None)
        or row.data.get("session") != getattr(user, "_auth_session_id", None)
    ):
        raise DomainError("IDEMPOTENCY_CONFLICT", "请求内容或账号已变化", 409)
    if aware(row.created_at) < now() - timedelta(minutes=5):
        raise DomainError("REQUEST_EXPIRED", "请求恢复期限已过，请重新验证", 409)
    result = dict(row.data["result"])
    if row.data.get("issued_session"):
        session = db.get(AuthSession, row.data["issued_session"])
        owner = db.get(User, session.subject_id) if session else None
        if not session or session.revoked or not owner:
            raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)
        account_available(db, owner)
        result.update(session_tokens(owner, db, session))
    if row.data.get("continuation"):
        result["continuation_token"] = digest("continuation:" + payload["transaction_id"])
    if row.data.get("verification"):
        result["verification_ticket"] = digest("verification-ticket:" + payload["challenge_id"])
    if row.data.get("transaction"):
        result["transaction_id"] = digest("oauth-transaction:" + key)
    return result


def remember_result(db, scope, key, payload, result, user=None):
    import json

    from fastapi.encoders import jsonable_encoder

    from app.core.security import token_claims

    if not key:
        return
    public = {
        k: v
        for k, v in result.items()
        if k
        not in {
            "access_token",
            "refresh_token",
            "continuation_token",
            "verification_ticket",
            "transaction_id",
        }
    }
    row = state(db, "result:" + digest(scope + ":" + key), "idempotency")
    change_state(
        row,
        proof=digest(json.dumps(payload, sort_keys=True, default=str)),
        subject=getattr(user, "id", None),
        session=getattr(user, "_auth_session_id", None),
        result=jsonable_encoder(public),
        continuation=bool(result.get("continuation_token")),
        verification=bool(result.get("verification_ticket")),
        transaction=bool(result.get("transaction_id")),
        issued_session=token_claims(result["access_token"])["sid"]
        if result.get("access_token")
        else None,
    )


def require_active_session(db, user):
    if db.get(AuthSession, user._auth_session_id).revoked:
        raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)


def phone_valid(phone):
    if not isinstance(phone, str) or not re.fullmatch(r"1[3-9]\d{9}", phone):
        raise DomainError("INVALID_PHONE", "请输入有效的大陆手机号")
    return phone


def mask(value):
    return value[:3] + "****" + value[-4:] if value and len(value) >= 8 else "—"


def config(db):
    return state(db, "test-code:" + get_settings().environment, "test-config")


def whitelist(db, phone):
    return db.scalar(
        select(LoginWhitelist).where(
            LoginWhitelist.phone == phone, LoginWhitelist.environment == get_settings().environment
        )
    )


def effective(db, row):
    cfg = config(db)
    return bool(
        row
        and row.enabled
        and aware(row.expires_at) > now()
        and cfg.data.get("enabled")
        and cfg.data.get("code_hash")
        and not get_settings().is_production
    )


def config_public(db):
    c = config(db)
    return {
        "environment": get_settings().environment,
        "enabled": bool(c.data.get("enabled") and not get_settings().is_production),
        "configured": bool(c.data.get("code_hash")),
        "version": c.version,
        "updated_at": c.updated_at,
        "updated_by": c.data.get("updated_by"),
    }


def user_payload(user, db=None):
    st = db.get(AuthState, "user:" + user.id) if db else None
    return {
        "id": user.id,
        "display_name": user.display_name,
        "avatar_url": user.avatar_url,
        "role": "user",
        "phone_masked": mask(user.phone),
        # Historical accounts predate the onboarding flag. Only genuinely new
        # registrations are initialized as incomplete; never reset existing assets.
        "onboarding_completed": bool(st.data.get("onboarding_completed", True)) if st else True,
        "password_setup_required": bool(st.data.get("password_setup_required", False))
        if st
        else False,
    }


def revoke(db, subject, audience="app"):
    db.execute(
        update(AuthSession)
        .where(AuthSession.subject_id == subject, AuthSession.audience == audience)
        .values(revoked=True)
    )


def issue_tokens(user, db, audience="app", authenticated_at=None):
    session = AuthSession(
        subject_id=user.id,
        audience=audience,
        expires_at=now() + timedelta(days=get_settings().refresh_token_days),
        refresh_hash="",
    )
    db.add(session)
    db.flush()
    if audience == "app":
        change_state(
            state(db, "session-auth:" + session.id, "session-auth"),
            authenticated_at=(authenticated_at or now()).isoformat(),
        )
    return session_tokens(user, db, session)


def session_authenticated_at(db, session):
    record = db.get(AuthState, "session-auth:" + session.id)
    if record and record.data.get("authenticated_at"):
        return aware(datetime.fromisoformat(record.data["authenticated_at"]))
    return aware(session.created_at)


def session_tokens(user, db, session):
    audience = session.audience
    refresh = create_token(user.id, "refresh", audience, session.id, session.created_at)
    session.refresh_hash = digest(refresh)
    return {
        "token_type": "Bearer",
        "access_token": create_token(user.id, "access", audience, session.id, session.created_at),
        "refresh_token": refresh,
        "expires_in": get_settings().access_token_minutes * 60,
        "user": user_payload(user, db)
        if audience == "app"
        else {"id": user.id, "name": user.display_name, "role": user.role},
        **(
            {
                "onboarding_completed": user_payload(user, db)["onboarding_completed"],
                "password_setup_required": user_payload(user, db)["password_setup_required"],
            }
            if audience == "app"
            else {}
        ),
    }


def request_code(db, phone, purpose="login", user=None, ip="", device="", idempotency_key=None):
    phone_valid(phone)
    if purpose not in PURPOSES:
        raise DomainError("INVALID_PURPOSE", "不支持的验证码用途")
    if purpose in SENSITIVE:
        if user is None:
            raise DomainError("AUTH_REQUIRED", "请先登录", 401)
        if purpose != "change_phone_new" and phone != user.phone:
            raise DomainError("PHONE_MISMATCH", "请验证当前账号手机号")
    lock(db)
    cached = cached_result(
        db, "challenge", idempotency_key, {"phone": phone, "purpose": purpose}, user
    )
    if cached is not None:
        return cached
    recent = list(
        db.scalars(
            select(VerificationChallenge).where(
                VerificationChallenge.phone == phone,
                VerificationChallenge.created_at > now() - timedelta(days=1),
            )
        )
    )
    if (
        any(aware(c.created_at) > now() - timedelta(seconds=60) for c in recent)
        or len(recent) >= 10
        or sum(aware(c.created_at) > now() - timedelta(hours=1) for c in recent) >= 5
    ):
        raise DomainError("RATE_LIMITED", "请求过于频繁，请稍后重试", 429)
    # Shared IP alone does not block households; combined IP + device is bounded too.
    risk_count = len(
        list(
            db.scalars(
                select(VerificationChallenge.id).where(
                    VerificationChallenge.ip_hash == digest(ip),
                    VerificationChallenge.device_hash == digest(device),
                    VerificationChallenge.created_at > now() - timedelta(hours=1),
                )
            )
        )
    )
    if risk_count >= 25:
        raise DomainError("RATE_LIMITED", "请求过于频繁，请稍后重试", 429)
    wl = whitelist(db, phone)
    test = purpose not in SENSITIVE and effective(db, wl)
    cfg = config(db)
    code = f"{secrets.randbelow(1000000):06d}"
    challenge = VerificationChallenge(
        phone=phone,
        purpose=purpose,
        mode="test_code" if test else "sms",
        code_hash=cfg.data["code_hash"] if test else secret_hash(code),
        expires_at=now() + timedelta(minutes=5),
        subject_id=user.id if user else None,
        session_id=getattr(user, "_auth_session_id", None),
        config_version=cfg.version if test else None,
        whitelist_version=wl.version if test else None,
        ip_hash=digest(ip),
        device_hash=digest(device),
    )
    db.add(challenge)
    db.flush()
    try:
        status = "accepted" if test else providers.send_sms(phone, code)
    except DomainError:
        challenge.consumed = True
        db.commit()
        raise
    if status == "failed":
        challenge.consumed = True
        db.commit()  # failed requests still count toward abuse limits; keep old valid code
        raise DomainError("SMS_DELIVERY_FAILED", "短信受理失败，请稍后重试", 503)
    challenge.delivered = True
    if status == "accepted":
        db.execute(
            update(VerificationChallenge)
            .where(
                VerificationChallenge.phone == phone,
                VerificationChallenge.purpose == purpose,
                VerificationChallenge.id != challenge.id,
            )
            .values(consumed=True)
        )
    result = {
        "challenge_id": challenge.id,
        "expires_in": 300,
        "retry_after": 60,
        "server_time": now().isoformat(),
        "retry_at": (now() + timedelta(seconds=60)).isoformat(),
        "delivery_mode": "test_code"
        if test
        else ("sms" if status == "accepted" else "sms_pending"),
    }
    remember_result(
        db, "challenge", idempotency_key, {"phone": phone, "purpose": purpose}, result, user
    )
    db.commit()
    return result


def consume_challenge(db, challenge_id, code, purpose, user=None, phone=None):
    row = db.get(VerificationChallenge, challenge_id)
    if not row or row.purpose != purpose or (phone and row.phone != phone):
        raise DomainError("VERIFICATION_PURPOSE_MISMATCH", "验证码用途或手机号不匹配")
    if row.subject_id != getattr(user, "id", None) or row.session_id != getattr(
        user, "_auth_session_id", None
    ):
        raise DomainError("VERIFICATION_PURPOSE_MISMATCH", "验证操作与当前账号不匹配")
    if row.consumed or not row.delivered or row.attempts >= 5 or aware(row.expires_at) <= now():
        raise DomainError("CHALLENGE_EXPIRED", "验证码已失效，请重新获取")
    if row.mode == "test_code":
        wl, cfg = whitelist(db, row.phone), config(db)
        if (
            purpose in SENSITIVE
            or not effective(db, wl)
            or cfg.version != row.config_version
            or wl.version != row.whitelist_version
        ):
            raise DomainError("CHALLENGE_EXPIRED", "测试验证已失效，请重新获取")
    if not re.fullmatch(r"\d{6}", code or "") or not check_secret(code, row.code_hash):
        row.attempts += 1
        owner = db.scalar(select(User).where(User.phone == row.phone))
        audit(
            db,
            "login.failed",
            user_id=owner.id if owner else None,
            channel=purpose,
            method=row.mode,
            result="invalid_code",
            error_code="INVALID_VERIFICATION_CODE",
            phone_masked=mask(row.phone),
        )
        db.commit()
        raise DomainError("INVALID_VERIFICATION_CODE", "验证码不正确")
    row.consumed = True
    return row


def get_or_create_user(db, phone):
    user = db.scalar(select(User).where(User.phone == phone))
    new = user is None
    if new:
        user = User(id=new_id("user"), phone=phone, display_name=f"Fan {phone[-4:]}")
        db.add(user)
        db.flush()
        change_state(
            state(db, "user:" + user.id),
            onboarding_completed=False,
            password_setup_required=True,
        )
    account_available(db, user)
    return user, new


def set_initial_password(db, user, password, idempotency_key=None):
    if (
        not isinstance(password, str)
        or not 8 <= len(password) <= 64
        or not re.search(r"[A-Za-z]", password)
        or not re.search(r"[0-9]", password)
        or any(c.isspace() for c in password)
    ):
        raise DomainError("INVALID_PASSWORD", "密码需为 8–64 位，包含字母和数字，不能含空格")
    lock(db)
    cached = cached_result(db, "password-setup", idempotency_key, {"password": password}, user)
    if cached is not None:
        return cached
    session = db.get(AuthSession, user._auth_session_id)
    if session_authenticated_at(db, session) < now() - timedelta(minutes=15):
        raise DomainError("REAUTHENTICATION_REQUIRED", "请重新登录后设置密码", 403)
    password_state = state(db, "user-password:" + user.id, "app-password")
    if password_state.data.get("password_hash"):
        raise DomainError("PASSWORD_ALREADY_SET", "已设置密码，不能通过首次登记覆盖", 409)
    change_state(password_state, password_hash=secret_hash(password))
    change_state(state(db, "user:" + user.id), password_setup_required=False)
    # Initial setup is not an unverified password-reset endpoint. Existing sessions
    # other than the freshly authenticated caller are invalidated on adding a password.
    db.execute(
        update(AuthSession)
        .where(
            AuthSession.subject_id == user.id,
            AuthSession.audience == "app",
            AuthSession.id != session.id,
        )
        .values(revoked=True)
    )
    result = {
        "password_setup_required": False,
        "onboarding_completed": user_payload(user, db)["onboarding_completed"],
    }
    remember_result(db, "password-setup", idempotency_key, {"password": password}, result, user)
    audit(db, "account.password_set", user, user.id, result="success")
    db.commit()
    return result


def login_password(db, phone, password, ip="", idempotency_key=None):
    phone_valid(phone)
    lock(db)
    payload = {"phone": phone, "password": password}
    cached = cached_result(db, "password-login", idempotency_key, payload)
    if cached is not None:
        return cached
    risks = [
        (state(db, "password-risk:phone:" + digest(phone), "password-risk"), 10),
        (state(db, "password-risk:ip:" + digest(ip), "password-risk"), 50),
    ]
    for risk, limit in risks:
        recent = risk.data.get("since") and datetime.fromisoformat(
            risk.data["since"]
        ) > now() - timedelta(minutes=15)
        if recent and risk.data.get("attempts", 0) >= limit:
            raise DomainError("RATE_LIMITED", "登录尝试过多，请稍后重试", 429)
    user = db.scalar(select(User).where(User.phone == phone))
    password_state = db.get(AuthState, "user-password:" + user.id) if user else None
    hashed = password_state.data.get("password_hash") if password_state else None
    valid = check_secret(password or "", hashed or _DUMMY_PASSWORD_HASH)
    if not user or not hashed or not valid or not user.is_active:
        for risk, _ in risks:
            recent = risk.data.get("since") and datetime.fromisoformat(
                risk.data["since"]
            ) > now() - timedelta(minutes=15)
            attempts = risk.data.get("attempts", 0) if recent else 0
            change_state(
                risk,
                attempts=attempts + 1,
                since=risk.data["since"] if attempts else now().isoformat(),
            )
        audit(
            db,
            "login.failed",
            user_id=user.id if user else None,
            channel="phone",
            method="password",
            result="invalid_credentials",
            error_code="PASSWORD_LOGIN_FAILED",
            phone_masked=mask(phone),
        )
        db.commit()
        raise DomainError(
            "PASSWORD_LOGIN_FAILED", "手机号或密码不正确，请重试或使用验证码登录", 401
        )
    account_available(db, user)
    # Clear only the account counter; successful logins must not clear an IP's
    # accumulated attempts against other accounts.
    change_state(risks[0][0], attempts=0, since=now().isoformat())
    change_state(
        state(db, "user:" + user.id),
        last_login_at=now().isoformat(),
        last_login_channel="phone",
        last_auth_method="password",
    )
    result = {**issue_tokens(user, db), "is_new_user": False}
    remember_result(db, "password-login", idempotency_key, payload, result)
    audit(
        db, "login.success", user_id=user.id, channel="phone", method="password", result="success"
    )
    db.commit()
    return result


def login(
    db,
    method,
    phone,
    code=None,
    challenge_id=None,
    idempotency_key=None,
    password=None,
    ip="",
    **kwargs,
):
    if method == "password":
        return login_password(db, phone, password, ip, idempotency_key)
    if method != "phone":
        raise DomainError("OAUTH_REQUIRED", "请使用平台授权事务")
    if not challenge_id:
        raise DomainError("CHALLENGE_REQUIRED", "请先获取验证码")
    lock(db)
    proof = digest(str(phone) + ":" + str(challenge_id) + ":" + str(code))
    saved = (
        db.get(AuthState, "login-result:" + digest(idempotency_key)) if idempotency_key else None
    )
    if saved:
        if saved.data.get("proof") != proof:
            raise DomainError("IDEMPOTENCY_CONFLICT", "请求内容已变化，请重新验证", 409)
        session = db.get(AuthSession, saved.data["session_id"])
        user = db.get(User, session.subject_id) if session else None
        if (
            not session
            or session.revoked
            or not user
            or aware(saved.created_at) < now() - timedelta(minutes=5)
        ):
            raise DomainError("CHALLENGE_EXPIRED", "请重新获取验证码")
        account_available(db, user)
        return {**session_tokens(user, db, session), "is_new_user": saved.data["is_new_user"]}
    challenge = consume_challenge(db, challenge_id, code, "login", phone=phone_valid(phone))
    user = db.scalar(select(User).where(User.phone == challenge.phone))
    if user and not user.is_active:
        audit(
            db,
            "login.failed",
            user_id=user.id,
            channel="phone",
            method=challenge.mode,
            result="banned",
            error_code="ACCOUNT_BANNED",
        )
        db.commit()
        account_available(db, user)
    user, is_new = get_or_create_user(db, challenge.phone)
    if challenge.mode == "test_code":
        whitelist(db, challenge.phone).last_login_at = now()
    change_state(
        state(db, "user:" + user.id),
        last_login_at=now().isoformat(),
        last_login_channel="phone",
        last_auth_method=challenge.mode,
    )
    result = {**issue_tokens(user, db), "is_new_user": is_new}
    result["onboarding_completed"] = result["user"]["onboarding_completed"]
    if idempotency_key:
        from app.core.security import token_claims

        item = state(db, "login-result:" + digest(idempotency_key), "idempotency")
        change_state(
            item,
            proof=proof,
            session_id=token_claims(result["access_token"])["sid"],
            is_new_user=is_new,
        )
    audit(
        db,
        "login.success",
        user_id=user.id,
        channel="phone",
        method=challenge.mode,
        result="success",
    )
    db.commit()
    return result


def refresh(db, refresh_token, audience="app", idempotency_key=None):
    lock(db)
    actor, session = resolve_session(
        db, refresh_token, audience, "refresh", allow_revoked=bool(idempotency_key)
    )
    cache_id = (
        "refresh-result:" + digest(audience + ":" + idempotency_key) if idempotency_key else None
    )
    saved = db.get(AuthState, cache_id) if cache_id else None
    if saved:
        if (
            saved.data.get("proof") != digest(refresh_token)
            or saved.data.get("prior_session") != session.id
        ):
            raise DomainError("IDEMPOTENCY_CONFLICT", "刷新请求已变化", 409)
        replacement = db.get(AuthSession, saved.data["issued_session"])
        if (
            not replacement
            or replacement.revoked
            or aware(saved.created_at) < now() - timedelta(minutes=5)
        ):
            raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)
        return session_tokens(actor, db, replacement)
    if session.revoked:
        raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)
    if not secrets.compare_digest(session.refresh_hash, digest(refresh_token)):
        raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)
    session.revoked = True
    # Refresh rotates the session, not the proof of user authentication. Inherit
    # the original authentication time so it cannot unlock sensitive setup.
    result = issue_tokens(actor, db, audience, session_authenticated_at(db, session))
    if cache_id:
        from app.core.security import token_claims

        saved = state(db, cache_id, "idempotency")
        change_state(
            saved,
            proof=digest(refresh_token),
            prior_session=session.id,
            issued_session=token_claims(result["access_token"], audience=audience)["sid"],
        )
    db.commit()
    return result


def create_ticket(db, challenge_id, code, user=None, idempotency_key=None):
    lock(db)
    body = {"challenge_id": challenge_id, "code": code}
    cached = cached_result(db, "verification", idempotency_key, body, user)
    if cached is not None:
        return cached
    c = db.get(VerificationChallenge, challenge_id)
    if not c or c.purpose == "login":
        raise DomainError("VERIFICATION_PURPOSE_MISMATCH", "该验证码不能用于敏感验证")
    row = consume_challenge(db, challenge_id, code, c.purpose, user=user)
    token = digest("verification-ticket:" + challenge_id)
    state_row = state(db, "ticket:" + digest(token), "ticket")
    change_state(
        state_row,
        phone=row.phone,
        purpose=row.purpose,
        user_id=row.subject_id,
        session_id=row.session_id,
        mode=row.mode,
        config_version=row.config_version,
        whitelist_version=row.whitelist_version,
        expires_at=(now() + timedelta(minutes=5)).isoformat(),
        consumed=False,
    )
    result = {"verification_ticket": token, "expires_in": 300}
    remember_result(db, "verification", idempotency_key, body, result, user)
    db.commit()
    return result


def ticket(db, token, purpose, user=None, consume=True):
    row = db.get(AuthState, "ticket:" + digest(token or ""))
    if (
        not row
        or row.data.get("consumed")
        or datetime.fromisoformat(row.data["expires_at"]) <= now()
    ):
        raise DomainError("VERIFICATION_EXPIRED", "身份验证已失效，请重新验证")
    if (
        row.data["purpose"] != purpose
        or row.data.get("user_id") != getattr(user, "id", None)
        or row.data.get("session_id") != getattr(user, "_auth_session_id", None)
    ):
        raise DomainError("VERIFICATION_PURPOSE_MISMATCH", "身份验证用途或账号不匹配")
    if consume:
        change_state(row, consumed=True)
    if row.data.get("mode") == "test_code":
        wl, cfg = whitelist(db, row.data["phone"]), config(db)
        if (
            not effective(db, wl)
            or cfg.version != row.data.get("config_version")
            or wl.version != row.data.get("whitelist_version")
        ):
            raise DomainError("VERIFICATION_EXPIRED", "测试验证已失效，请重新验证")
    return row
