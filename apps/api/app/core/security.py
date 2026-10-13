from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.common.response import DomainError
from app.core.config import get_settings
from app.core.database import get_db
from app.models import User

bearer = HTTPBearer(auto_error=False)


def create_token(subject: str, token_type: str) -> str:
    settings = get_settings()
    lifetime = (
        timedelta(minutes=settings.access_token_minutes)
        if token_type == "access"
        else timedelta(days=settings.refresh_token_days)
    )
    payload: dict[str, Any] = {
        "sub": subject,
        "type": token_type,
        "iat": datetime.now(UTC),
        "exp": datetime.now(UTC) + lifetime,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str, expected_type: str = "access") -> str:
    settings = get_settings()
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except jwt.PyJWTError as exc:
        raise DomainError("INVALID_TOKEN", "登录状态已失效", 401) from exc
    if payload.get("type") != expected_type or not payload.get("sub"):
        raise DomainError("INVALID_TOKEN", "登录状态已失效", 401)
    return str(payload["sub"])


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None:
        raise DomainError("AUTH_REQUIRED", "请先登录", 401)
    user_id = decode_token(credentials.credentials)
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise DomainError("USER_UNAVAILABLE", "用户不存在或已停用", 401)
    return user


def current_admin(user: User = Depends(current_user)) -> User:
    if user.role not in {"admin", "content_operator", "operation_admin"}:
        raise DomainError("ADMIN_REQUIRED", "需要管理员权限", 403)
    return user


def optional_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User | None:
    return current_user(credentials, db) if credentials else None
