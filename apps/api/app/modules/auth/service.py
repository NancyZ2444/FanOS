from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.response import DomainError
from app.core.config import get_settings
from app.core.security import create_token, decode_token
from app.models import User


def user_payload(user: User) -> dict[str, object]:
    return {
        "id": user.id,
        "display_name": user.display_name,
        "avatar_url": user.avatar_url,
        "role": user.role,
    }


def login(db: Session, method: str, phone: str | None, code: str | None) -> dict[str, object]:
    settings = get_settings()
    if settings.is_production:
        raise DomainError("AUTH_PROVIDER_NOT_CONFIGURED", "生产环境需配置真实身份验证服务", 503)
    if method not in {"phone", "wechat", "weibo"}:
        raise DomainError("UNSUPPORTED_LOGIN_METHOD", "暂不支持该登录方式")
    if method == "phone" and code not in {None, settings.dev_phone_code}:
        raise DomainError("INVALID_VERIFICATION_CODE", "验证码不正确")
    lookup_phone = phone or "13800000000"
    user = db.scalar(select(User).where(User.phone == lookup_phone))
    if user is None:
        user = User(
            id=f"user-{lookup_phone}",
            phone=lookup_phone,
            display_name=f"Fan {lookup_phone[-4:]}",
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    if not user.is_active:
        raise DomainError("USER_UNAVAILABLE", "账号已被停用", 401)
    return issue_tokens(user)


def issue_tokens(user: User) -> dict[str, object]:
    return {
        "token_type": "Bearer",
        "access_token": create_token(user.id, "access"),
        "refresh_token": create_token(user.id, "refresh"),
        "expires_in": get_settings().access_token_minutes * 60,
        "user": user_payload(user),
    }


def refresh(db: Session, refresh_token: str) -> dict[str, object]:
    user_id = decode_token(refresh_token, "refresh")
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise DomainError("USER_UNAVAILABLE", "用户不存在或已停用", 401)
    return issue_tokens(user)
