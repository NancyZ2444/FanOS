"""Authentication boundaries; deliberately independent of business User primary keys."""

from datetime import datetime
from typing import Any

from sqlalchemy import JSON, Boolean, DateTime, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.models import TimestampMixin, new_id


class AdminPrincipal(Base, TimestampMixin):
    __tablename__ = "auth_admin_principals"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("adm"))
    account: Mapped[str] = mapped_column(String(100), unique=True)
    display_name: Mapped[str] = mapped_column(String(100))
    password_hash: Mapped[str] = mapped_column(Text)
    role: Mapped[str] = mapped_column(String(30), default="admin")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AuthSession(Base, TimestampMixin):
    __tablename__ = "auth_sessions"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("ses"))
    subject_id: Mapped[str] = mapped_column(String(64), index=True)
    audience: Mapped[str] = mapped_column(String(20), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)
    refresh_hash: Mapped[str] = mapped_column(String(128))


class AuthState(Base, TimestampMixin):
    """Small versioned config/transaction/account-state records, no raw credentials."""

    __tablename__ = "auth_state"
    id: Mapped[str] = mapped_column(String(180), primary_key=True)
    kind: Mapped[str] = mapped_column(String(40), index=True)
    data: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    version: Mapped[int] = mapped_column(Integer, default=1)


class VerificationChallenge(Base, TimestampMixin):
    __tablename__ = "auth_challenges"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("vc"))
    phone: Mapped[str] = mapped_column(String(32), index=True)
    purpose: Mapped[str] = mapped_column(String(40))
    mode: Mapped[str] = mapped_column(String(20))
    code_hash: Mapped[str] = mapped_column(Text)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    consumed: Mapped[bool] = mapped_column(Boolean, default=False)
    delivered: Mapped[bool] = mapped_column(Boolean, default=False)
    subject_id: Mapped[str | None] = mapped_column(String(64))
    session_id: Mapped[str | None] = mapped_column(String(64))
    config_version: Mapped[int | None] = mapped_column(Integer)
    whitelist_version: Mapped[int | None] = mapped_column(Integer)
    ip_hash: Mapped[str] = mapped_column(String(128), default="")
    device_hash: Mapped[str] = mapped_column(String(128), default="")


class LoginWhitelist(Base, TimestampMixin):
    __tablename__ = "auth_login_whitelist"
    __table_args__ = (UniqueConstraint("phone", "environment"),)
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("wl"))
    phone: Mapped[str] = mapped_column(String(32))
    environment: Mapped[str] = mapped_column(String(40))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    owner: Mapped[str] = mapped_column(String(100))
    purpose: Mapped[str] = mapped_column(String(500))
    version: Mapped[int] = mapped_column(Integer, default=1)
    updated_by: Mapped[str] = mapped_column(String(64))
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class TrustedIdentity(Base, TimestampMixin):
    __tablename__ = "auth_trusted_identities"
    __table_args__ = (
        UniqueConstraint("provider", "app_scope", "subject"),
        UniqueConstraint("user_id", "provider"),
    )
    id: Mapped[str] = mapped_column(
        String(64), primary_key=True, default=lambda: new_id("identity")
    )
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    provider: Mapped[str] = mapped_column(String(20))
    app_scope: Mapped[str] = mapped_column(String(100))
    subject: Mapped[str] = mapped_column(String(180))
    display_name: Mapped[str] = mapped_column(String(180), default="")
    profile_url: Mapped[str | None] = mapped_column(String(500))
    authorization_status: Mapped[str] = mapped_column(String(20), default="unknown")
    authorization_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    version: Mapped[int] = mapped_column(Integer, default=1)


class AuthAudit(Base, TimestampMixin):
    __tablename__ = "auth_audit"
    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: new_id("audit"))
    user_id: Mapped[str | None] = mapped_column(String(64), index=True)
    actor_id: Mapped[str | None] = mapped_column(String(64))
    action: Mapped[str] = mapped_column(String(60), index=True)
    data: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
