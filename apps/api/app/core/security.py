from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.auth_models import AdminPrincipal, AuthSession, AuthState
from app.common.response import DomainError
from app.core.config import get_settings
from app.core.database import get_db
from app.models import User

bearer = HTTPBearer(auto_error=False)


def aware(value):
    return value.replace(tzinfo=UTC) if value and value.tzinfo is None else value


def secret_hash(value: str) -> str:
    salt = secrets.token_hex(16)
    hashed = hashlib.pbkdf2_hmac("sha256", value.encode(), salt.encode(), 210000).hex()
    return salt + "$" + hashed


def check_secret(value: str, hashed: str) -> bool:
    try:
        salt, expected = hashed.split("$")
        actual = hashlib.pbkdf2_hmac("sha256", value.encode(), salt.encode(), 210000).hex()
        return hmac.compare_digest(actual, expected)
    except (ValueError, AttributeError):
        return False


def digest(value: str) -> str:
    return hmac.new(get_settings().jwt_secret.encode(), value.encode(), hashlib.sha256).hexdigest()


def create_token(
    subject: str,
    token_type: str,
    audience: str = "app",
    session_id: str | None = None,
    issued_at=None,
) -> str:
    settings = get_settings()
    lifetime = (
        timedelta(minutes=settings.access_token_minutes)
        if token_type == "access"
        else timedelta(days=settings.refresh_token_days)
    )
    issued_at = aware(issued_at) or datetime.now(UTC)
    payload = {
        "sub": subject,
        "type": token_type,
        "aud": audience,
        "sid": session_id,
        "jti": digest(str(session_id) + token_type),
        "iat": issued_at,
        "exp": issued_at + lifetime,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def token_claims(token: str, expected_type: str = "access", audience: str = "app") -> dict:
    settings = get_settings()
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
            audience=audience,
            options={"require": ["sub", "aud", "sid", "exp", "iat"]},
        )
    except jwt.PyJWTError as exc:
        raise DomainError("INVALID_TOKEN", "登录状态已失效", 401) from exc
    if payload.get("type") != expected_type or not payload.get("sid"):
        raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)
    return payload


def decode_token(token: str, expected_type: str = "access") -> str:
    return str(token_claims(token, expected_type)["sub"])


def account_available(db: Session, user: User):
    if not user.is_active:
        state = db.get(AuthState, f"user:{user.id}")
        values = state.data if state else {}
        error = DomainError(
            "ACCOUNT_BANNED", "当前账号暂时无法登录。如有疑问，请联系客服申请核查。", 403
        )
        error.public_data = {
            "public_message": values.get("public_message") or error.message,
            "banned_until": values.get("banned_until"),
            "support_entry_id": "login-support",
        }
        raise error
    if not user.phone:
        raise DomainError("PHONE_REQUIRED", "请先完成手机号验证", 403)


def resolve_session(
    db: Session, token: str, audience: str = "app", token_type: str = "access", allow_revoked=False
):
    claims = token_claims(token, token_type, audience)
    session = db.get(AuthSession, claims["sid"])
    if (
        not session
        or session.audience != audience
        or session.subject_id != claims["sub"]
        or aware(session.expires_at) <= datetime.now(UTC)
    ):
        raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)
    actor = db.get(User if audience == "app" else AdminPrincipal, session.subject_id)
    if actor is None:
        raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)
    if audience == "app":
        account_available(db, actor)
    elif not actor.is_active:
        raise DomainError("ADMIN_UNAVAILABLE", "后台账号已停用", 403)
    if session.revoked and not allow_revoked:
        raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)
    actor._auth_session_id = session.id
    return actor, session


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None:
        raise DomainError("AUTH_REQUIRED", "请先登录", 401)
    return resolve_session(db, credentials.credentials)[0]


def current_admin(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> AdminPrincipal:
    if credentials is None:
        raise DomainError("AUTH_REQUIRED", "请登录后台", 401)
    return resolve_session(db, credentials.credentials, "admin")[0]


def recovery_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    """Only used by credential-rotation endpoints; route MUST check cached proof first."""
    if credentials is None:
        raise DomainError("AUTH_REQUIRED", "请先登录", 401)
    return resolve_session(db, credentials.credentials, allow_revoked=True)[0]


def optional_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User | None:
    return current_user(credentials, db) if credentials else None
