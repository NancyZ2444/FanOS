import re
from datetime import datetime
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field, SecretStr, StrictBool
from sqlalchemy import false, func, or_, select
from sqlalchemy.orm import Session

from app.auth_models import (
    AdminPrincipal,
    AuthAudit,
    AuthSession,
    AuthState,
    LoginWhitelist,
    TrustedIdentity,
)
from app.common.response import DomainError, success
from app.core.config import get_settings
from app.core.database import get_db
from app.core.security import aware, check_secret, current_admin, secret_hash
from app.models import User, UserCollectionItem, UserWishlistItem
from app.modules.auth import service as s
from app.modules.auth.router import identity_payload, support

router = APIRouter(prefix="/admin/auth", tags=["Account Operations"])
PERMISSIONS = [
    "auth.users.view",
    "auth.users.manage",
    "auth.users.password",
    "auth.users.sensitive",
    "auth.identities.unbind",
    "auth.whitelist.manage",
    "auth.test_code.manage",
    "auth.support.manage",
    "auth.admins.manage",
]


def permissions(actor):
    from app.modules.admin.permissions import effective

    return [key for key in effective(actor) if key in PERMISSIONS]


def permit(actor, capability):
    if capability not in permissions(actor):
        raise DomainError("PERMISSION_DENIED", "当前角色无此操作权限", 403)


def reason_check(value):
    if not value or not value.strip():
        raise DomainError("REASON_REQUIRED", "请填写操作原因")
    if re.search(r"(?<!\d)\d{6}(?!\d)", value):
        raise DomainError("SENSITIVE_REASON", "原因中不得包含验证码")
    return value.strip()[:1000]


def version_check(row, version):
    if row.version != version:
        raise DomainError("CONFIG_VERSION_CONFLICT", "数据已变化，请刷新后重试", 409)


class AdminLogin(BaseModel):
    account: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=1, max_length=256)


@router.post("/login")
def login(payload: AdminLogin, request: Request, db: Session = Depends(get_db)):
    from datetime import timedelta

    s.lock(db)
    risk = s.state(
        db,
        "admin-risk:"
        + s.digest(payload.account.lower() + ":" + (request.client.host if request.client else "")),
        "admin-risk",
    )
    since = risk.data.get("since")
    if (
        since
        and datetime.fromisoformat(since) > s.now() - timedelta(minutes=15)
        and risk.data.get("attempts", 0) >= 10
    ):
        raise DomainError("RATE_LIMITED", "登录尝试过多，请稍后重试", 429)
    actor = db.scalar(select(AdminPrincipal).where(AdminPrincipal.account == payload.account))
    if not actor or not check_secret(payload.password, actor.password_hash) or not actor.is_active:
        attempts = (
            risk.data.get("attempts", 0)
            if since and datetime.fromisoformat(since) > s.now() - timedelta(minutes=15)
            else 0
        )
        s.change_state(
            risk, attempts=attempts + 1, since=since if attempts else s.now().isoformat()
        )
        db.commit()
        raise DomainError("ADMIN_LOGIN_FAILED", "后台账号或密码错误，或账号已停用", 401)
    actor.last_login_at = s.now()
    s.change_state(risk, attempts=0, since=s.now().isoformat())
    result = s.issue_tokens(actor, db, "admin")
    result["permissions"] = permissions(actor)
    s.audit(db, "admin.login", actor, result="success")
    db.commit()
    return success(result)


class RefreshRequest(BaseModel):
    refresh_token: str


@router.post("/refresh")
def refresh(payload: RefreshRequest, request: Request, db: Session = Depends(get_db)):
    return success(
        s.refresh(db, payload.refresh_token, "admin", request.headers.get("Idempotency-Key"))
    )


@router.post("/logout")
def logout(actor=Depends(current_admin), db: Session = Depends(get_db)):
    s.lock(db)
    db.get(AuthSession, actor._auth_session_id).revoked = True
    db.commit()
    return success()


@router.get("/meta")
def meta(actor=Depends(current_admin)):
    return success({"environment": get_settings().environment, "permissions": permissions(actor)})


@router.get("/test-login-config")
def read_config(actor=Depends(current_admin), db: Session = Depends(get_db)):
    permit(actor, "auth.test_code.manage")
    return success(s.config_public(db))


class ConfigPatch(BaseModel):
    enabled: bool
    default_code: str | None = None
    expected_version: int
    reason: str = Field(max_length=1000)


@router.patch("/test-login-config")
def patch_config(payload: ConfigPatch, actor=Depends(current_admin), db: Session = Depends(get_db)):
    permit(actor, "auth.test_code.manage")
    reason_check(payload.reason)
    s.lock(db)
    row = s.config(db)
    version_check(row, payload.expected_version)
    if get_settings().is_production and payload.enabled:
        raise DomainError("ENVIRONMENT_NOT_ALLOWED", "生产环境不允许启用测试验证码", 403)
    values = {}
    if payload.default_code:
        if not re.fullmatch(r"\d{6}", payload.default_code):
            raise DomainError("INVALID_TEST_CODE_FORMAT", "验证码必须是 6 位数字字符串")
        values["code_hash"] = secret_hash(payload.default_code)
    if payload.enabled and not (values or row.data.get("code_hash")):
        raise DomainError("TEST_CODE_NOT_CONFIGURED", "请先配置默认测试验证码")
    s.change_state(row, **values, enabled=payload.enabled, updated_by=actor.id)
    s.audit(
        db,
        "test_code.configure",
        actor,
        reason=payload.reason,
        enabled=payload.enabled,
        version=row.version,
    )
    db.commit()
    return success(s.config_public(db))


def wl_payload(db, row):
    user = db.scalar(select(User).where(User.phone == row.phone))
    return {
        "id": row.id,
        "phone_masked": s.mask(row.phone),
        "user_id": user.id if user else None,
        "user_name": user.display_name if user else None,
        "environment": row.environment,
        "enabled": row.enabled,
        "effective": s.effective(db, row),
        "version": row.version,
        "status": "expired"
        if aware(row.expires_at) <= s.now()
        else ("enabled" if row.enabled else "disabled"),
        "expires_at": row.expires_at,
        "owner": row.owner,
        "purpose": row.purpose,
        "last_test_login_at": row.last_login_at,
        "updated_by": row.updated_by,
        "updated_at": row.updated_at,
    }


def paging(items, page, page_size):
    page, page_size = max(page, 1), min(max(page_size, 1), 100)
    return {
        "items": items[(page - 1) * page_size : page * page_size],
        "total": len(items),
        "page": page,
        "page_size": page_size,
    }


def sql_page(db, query, page, page_size, serializer):
    page, page_size = max(page, 1), min(max(page_size, 1), 100)
    total = db.scalar(select(func.count()).select_from(query.order_by(None).subquery()))
    rows = db.scalars(query.offset((page - 1) * page_size).limit(page_size))
    return {
        "items": [serializer(row) for row in rows],
        "total": total,
        "page": page,
        "page_size": page_size,
    }


def date_filter(query, column, start, end):
    try:
        if start:
            query = query.where(column >= aware(datetime.fromisoformat(start)))
        if end:
            query = query.where(column <= aware(datetime.fromisoformat(end)))
        return query
    except ValueError as exc:
        raise DomainError("INVALID_DATE", "日期范围格式不正确") from exc


def in_range(value, start, end):
    target = aware(value)
    try:
        return (not start or target >= aware(datetime.fromisoformat(start))) and (
            not end or target <= aware(datetime.fromisoformat(end))
        )
    except ValueError as exc:
        raise DomainError("INVALID_DATE", "日期范围格式不正确") from exc


@router.get("/login-whitelist/match")
def match(
    phone: str | None = None,
    user_id: str | None = None,
    actor=Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "auth.whitelist.manage")
    user = (
        db.get(User, user_id)
        if user_id
        else db.scalar(select(User).where(User.phone == s.phone_valid(phone)))
    )
    value = user.phone if user_id and user else phone
    row = s.whitelist(db, value)
    return success(
        {
            "registered": bool(user),
            "user_id": user.id if user else None,
            "user_name": user.display_name if user else None,
            "phone_masked": s.mask(value),
            "whitelist_id": row.id if row else None,
        }
    )


class MatchRequest(BaseModel):
    phone: str | None = None
    user_id: str | None = None


@router.post("/login-whitelist/match")
def match_private(
    payload: MatchRequest, actor=Depends(current_admin), db: Session = Depends(get_db)
):
    return match(payload.phone, payload.user_id, actor, db)


@router.get("/login-whitelist")
def whitelists(
    q: str = "",
    user_id: str = "",
    status: str = "",
    registered: str = "",
    expires_from: str = "",
    expires_to: str = "",
    page: int = 1,
    page_size: int = 20,
    actor=Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "auth.whitelist.manage")
    env = get_settings().environment
    query = select(LoginWhitelist).where(LoginWhitelist.environment == env)
    if user_id:
        query = query.where(
            LoginWhitelist.phone == select(User.phone).where(User.id == user_id).scalar_subquery()
        )
    linked = select(User.id).where(User.phone == LoginWhitelist.phone).exists()
    if q:
        query = query.where(
            or_(
                LoginWhitelist.phone == q,
                LoginWhitelist.owner.contains(q),
                LoginWhitelist.purpose.contains(q),
                select(User.id).where(User.phone == LoginWhitelist.phone, User.id == q).exists(),
            )
        )
    if status == "expired":
        query = query.where(LoginWhitelist.expires_at <= s.now())
    elif status in {"enabled", "disabled"}:
        query = query.where(
            LoginWhitelist.enabled == (status == "enabled"), LoginWhitelist.expires_at > s.now()
        )
    if registered in {"true", "registered", "false", "unregistered"}:
        query = query.where(linked if registered in {"true", "registered"} else ~linked)
    query = date_filter(query, LoginWhitelist.expires_at, expires_from, expires_to)
    result = sql_page(
        db,
        query.order_by(LoginWhitelist.updated_at.desc(), LoginWhitelist.id),
        page,
        page_size,
        lambda row: wl_payload(db, row),
    )
    cfg = s.config_public(db)
    effective_count = (
        db.scalar(
            select(func.count())
            .select_from(LoginWhitelist)
            .where(
                LoginWhitelist.environment == env,
                LoginWhitelist.enabled.is_(True),
                LoginWhitelist.expires_at > s.now(),
            )
        )
        if cfg["enabled"] and cfg["configured"]
        else 0
    )
    return success(
        {
            **result,
            "environment": env,
            "enabled": cfg["enabled"],
            "effective_count": effective_count,
        }
    )


class WhitelistCreate(BaseModel):
    phone: str | None = None
    user_id: str | None = None
    expires_at: datetime
    owner: str = Field(min_length=1, max_length=100)
    purpose: str = Field(min_length=1, max_length=500)
    authorized: bool


@router.post("/login-whitelist")
def add_whitelist(
    payload: WhitelistCreate, actor=Depends(current_admin), db: Session = Depends(get_db)
):
    permit(actor, "auth.whitelist.manage")
    s.lock(db)
    user = db.get(User, payload.user_id) if payload.user_id else None
    if payload.user_id and not user:
        raise DomainError("USER_NOT_FOUND", "用户不存在", 404)
    phone = s.phone_valid(user.phone if user else payload.phone)
    if (
        not payload.authorized
        or aware(payload.expires_at) <= s.now()
        or not payload.owner.strip()
        or not payload.purpose.strip()
    ):
        raise DomainError("INVALID_WHITELIST", "请确认授权并填写负责人、用途及未来有效期")
    if s.whitelist(db, phone):
        raise DomainError("WHITELIST_EXISTS", "该号码已有白名单记录，请查看原记录", 409)
    row = LoginWhitelist(
        phone=phone,
        environment=get_settings().environment,
        expires_at=payload.expires_at,
        owner=payload.owner.strip(),
        purpose=payload.purpose.strip(),
        updated_by=actor.id,
    )
    db.add(row)
    db.flush()
    s.audit(
        db,
        "whitelist.create",
        actor,
        user.id if user else None,
        phone_masked=s.mask(phone),
        whitelist_id=row.id,
    )
    db.commit()
    return success(wl_payload(db, row))


def find_whitelist(db, item_id):
    row = db.get(LoginWhitelist, item_id)
    if not row or row.environment != get_settings().environment:
        raise DomainError("NOT_FOUND", "白名单记录不存在", 404)
    return row


@router.get("/login-whitelist/{item_id}")
def read_whitelist(item_id: str, actor=Depends(current_admin), db: Session = Depends(get_db)):
    permit(actor, "auth.whitelist.manage")
    return success(wl_payload(db, find_whitelist(db, item_id)))


class WhitelistPatch(BaseModel):
    expected_version: int
    expires_at: datetime | None = None
    owner: str | None = Field(default=None, min_length=1, max_length=100)
    purpose: str | None = Field(default=None, min_length=1, max_length=500)
    enabled: bool | None = None
    reason: str = Field(min_length=1, max_length=1000)


@router.patch("/login-whitelist/{item_id}")
def patch_whitelist(
    item_id: str,
    payload: WhitelistPatch,
    actor=Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "auth.whitelist.manage")
    reason_check(payload.reason)
    s.lock(db)
    row = find_whitelist(db, item_id)
    version_check(row, payload.expected_version)
    expiration = aware(payload.expires_at or row.expires_at)
    if (payload.enabled is True or payload.expires_at) and expiration <= s.now():
        raise DomainError("INVALID_EXPIRY", "请先延长有效期")
    if any(value is not None and not value.strip() for value in (payload.owner, payload.purpose)):
        raise DomainError("INVALID_WHITELIST", "负责人和用途不能留空")
    for key in ("owner", "purpose", "enabled", "expires_at"):
        value = getattr(payload, key)
        if value is not None:
            setattr(row, key, value)
    row.version += 1
    row.updated_by = actor.id
    s.audit(
        db,
        "whitelist.update",
        actor,
        phone_masked=s.mask(row.phone),
        reason=payload.reason,
        version=row.version,
    )
    db.commit()
    return success(wl_payload(db, row))


def user_row(db, user):
    st = db.get(AuthState, "user:" + user.id)
    data = st.data if st else {}
    wl = s.whitelist(db, user.phone)
    ids = {
        r.provider: r
        for r in db.scalars(select(TrustedIdentity).where(TrustedIdentity.user_id == user.id))
    }

    def count(model):
        return (
            db.scalar(select(func.count()).select_from(model).where(model.user_id == user.id)) or 0
        )

    return {
        "id": user.id,
        "name": user.display_name,
        "avatar_url": user.avatar_url,
        "phone_masked": s.mask(user.phone),
        "has_phone": bool(user.phone),
        "status": "normal" if user.is_active else "banned",
        "is_active": user.is_active,
        "created_at": user.created_at,
        "version": st.version if st else 1,
        "last_login_at": data.get("last_login_at"),
        "last_login_channel": data.get("last_login_channel"),
        "collection_count": count(UserCollectionItem),
        "wishlist_count": count(UserWishlistItem),
        "whitelist_id": wl.id if wl else None,
        "whitelist_effective": s.effective(db, wl),
        "wechat": identity_payload(ids.get("wechat"), "wechat"),
        "weibo": identity_payload(ids.get("weibo"), "weibo"),
        "qq": identity_payload(ids.get("qq"), "qq"),
        "weibo_visible": bool(user.weibo_visible and ids.get("weibo")),
    }


@router.get("/users")
def users(
    q: str = "",
    status: str = "",
    wechat: str = "",
    weibo: str = "",
    qq: str = "",
    whitelist: str = "",
    registered_from: str = "",
    registered_to: str = "",
    page: int = 1,
    page_size: int = 20,
    actor=Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "auth.users.view")
    query = select(User).order_by(User.created_at.desc())
    if q:
        query = query.where(or_(User.id == q, User.phone == q, User.display_name.contains(q)))
    if status in {"normal", "banned"}:
        query = query.where(User.is_active == (status == "normal"))
    query = date_filter(query, User.created_at, registered_from, registered_to)
    for provider, value in (("wechat", wechat), ("weibo", weibo), ("qq", qq)):
        bound = (
            select(TrustedIdentity.id)
            .where(TrustedIdentity.user_id == User.id, TrustedIdentity.provider == provider)
            .exists()
        )
        if value in {"bound", "unbound"}:
            query = query.where(bound if value == "bound" else ~bound)
    if whitelist in {"effective", "ineffective"}:
        cfg = s.config_public(db)
        active = (
            select(LoginWhitelist.id)
            .where(
                LoginWhitelist.phone == User.phone,
                LoginWhitelist.environment == get_settings().environment,
                LoginWhitelist.enabled.is_(True),
                LoginWhitelist.expires_at > s.now(),
            )
            .exists()
            if cfg["enabled"] and cfg["configured"]
            else false()
        )
        query = query.where(active if whitelist == "effective" else ~active)
    return success(sql_page(db, query, page, page_size, lambda row: user_row(db, row)))


def find_user(db, user_id):
    user = db.get(User, user_id)
    if not user:
        raise DomainError("USER_NOT_FOUND", "用户不存在", 404)
    return user


@router.get("/users/{user_id}")
def user_detail(user_id: str, actor=Depends(current_admin), db: Session = Depends(get_db)):
    permit(actor, "auth.users.view")
    user = find_user(db, user_id)
    base = user_row(db, user)
    st = db.get(AuthState, "user:" + user.id)
    records = [
        {
            "id": r.id,
            "time": r.created_at,
            "created_at": r.created_at,
            "action": r.action,
            "actor_id": r.actor_id,
            **r.data,
        }
        for r in db.scalars(
            select(AuthAudit)
            .where(AuthAudit.user_id == user.id)
            .order_by(AuthAudit.created_at.desc())
            .limit(100)
        )
    ]
    from app.common.serializers import profile_payload
    from app.models import Idol

    profile = profile_payload(db, user, user)
    favorites = []
    for idol_id in profile.get("favorite_idol_ids", []):
        idol = db.get(Idol, idol_id)
        if idol:
            favorites.append(
                {
                    "id": idol.id,
                    "name": idol.name_translated or idol.name or idol.name_ko or idol.name_en,
                }
            )
    return success(
        {
            "user": base,
            "version": base["version"],
            "identities": [base["wechat"], base["weibo"], base["qq"]],
            "stats": {
                "collection_count": base["collection_count"],
                "wishlist_count": base["wishlist_count"],
                "album_count": profile.get("album_count", 0),
                "photo_count": profile.get("photo_count", 0),
                "following_count": profile.get("following_count", 0),
                "follower_count": profile.get("followers_count", 0),
            },
            "bio": user.bio,
            "level": user.level,
            "experience": user.experience,
            "favorites": favorites,
            "internal_note": st.data.get("internal_note", "") if st else "",
            "login_records": [r for r in records if r["action"].startswith("login.")],
            "operation_records": [r for r in records if not r["action"].startswith("login.")],
        }
    )


class UserAction(BaseModel):
    action: str
    reason: str = Field(min_length=1, max_length=1000)
    expected_version: int
    public_message: str | None = Field(default=None, max_length=500)
    banned_until: datetime | None = None
    internal_note: str | None = Field(default=None, max_length=2000)


@router.post("/users/{user_id}/actions")
def user_action(
    user_id: str, payload: UserAction, actor=Depends(current_admin), db: Session = Depends(get_db)
):
    permit(actor, "auth.users.manage")
    reason_check(payload.reason)
    s.lock(db)
    user = find_user(db, user_id)
    st = s.state(db, "user:" + user.id)
    version_check(st, payload.expected_version)
    if payload.action not in {"ban", "unban", "revoke_sessions", "note"}:
        raise DomainError("INVALID_ACTION", "不支持的用户操作")
    if payload.action == "ban" and payload.banned_until and aware(payload.banned_until) <= s.now():
        raise DomainError("INVALID_EXPIRY", "封禁截止时间应晚于当前时间")
    values = {}
    if payload.action in {"ban", "unban"}:
        user.is_active = payload.action == "unban"
        values.update(
            public_message=payload.public_message if not user.is_active else None,
            banned_until=payload.banned_until.isoformat()
            if payload.banned_until and not user.is_active
            else None,
        )
        s.revoke(db, user.id)
    elif payload.action == "revoke_sessions":
        s.revoke(db, user.id)
    else:
        values["internal_note"] = payload.internal_note or ""
    s.change_state(st, **values)
    s.audit(db, "user." + payload.action, actor, user.id, reason=payload.reason, result="success")
    db.commit()
    return success(user_row(db, user))


class SensitiveRead(BaseModel):
    reason: str = Field(min_length=1, max_length=1000)


class UserPasswordReset(BaseModel):
    new_password: SecretStr = Field(min_length=8, max_length=64)
    reason: str = Field(min_length=1, max_length=1000)
    confirmed: StrictBool
    expected_version: int = Field(ge=1)


@router.post("/users/{user_id}/password-reset")
def user_password_reset(
    user_id: str,
    payload: UserPasswordReset,
    actor=Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "auth.users.password")
    if not payload.confirmed:
        raise DomainError("CONFIRMATION_REQUIRED", "请确认重置密码并下线全部 App 会话")
    password = payload.new_password.get_secret_value()
    if (
        not re.search(r"[A-Za-z]", password)
        or not re.search(r"[0-9]", password)
        or any(c.isspace() for c in password)
    ):
        raise DomainError("INVALID_PASSWORD", "密码需为 8–64 位，包含字母和数字，不能含空格")
    reason = reason_check(payload.reason)
    if password.casefold() in reason.casefold():
        raise DomainError("SENSITIVE_REASON", "处理原因中不得包含密码")
    s.lock(db)
    # Re-check delegated permission after waiting for the auth mutation lock.
    permit(actor, "auth.users.password")
    user = find_user(db, user_id)
    if not user.phone:
        raise DomainError("PHONE_REQUIRED", "用户须先绑定手机号，才能使用密码登录")
    account = s.state(db, "user:" + user.id)
    version_check(account, payload.expected_version)
    credential = s.state(db, "user-password:" + user.id, "app-password")
    s.change_state(credential, password_hash=secret_hash(password))
    s.change_state(account, password_setup_required=False)
    s.revoke(db, user.id, "app")
    s.audit(
        db,
        "user.password_reset",
        actor,
        user.id,
        reason=reason,
        result="success",
        sessions_revoked=True,
    )
    db.commit()
    return success({"user_id": user.id, "version": account.version, "sessions_revoked": True})


@router.post("/users/{user_id}/sensitive")
def user_sensitive(
    user_id: str,
    payload: SensitiveRead,
    actor=Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "auth.users.sensitive")
    reason_check(payload.reason)
    s.lock(db)
    user = find_user(db, user_id)
    s.audit(db, "user.phone.read", actor, user.id, reason=payload.reason)
    db.commit()
    return success({"phone": user.phone})


class AdminUnbind(SensitiveRead):
    ticket_number: str = Field(min_length=1, max_length=100)
    identity_verified: bool
    expected_version: int


@router.post("/users/{user_id}/identities/{provider}/unbind")
def identity_unbind(
    user_id: str,
    provider: str,
    payload: AdminUnbind,
    actor=Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "auth.identities.unbind")
    reason_check(payload.reason)
    if not payload.identity_verified:
        raise DomainError("VERIFICATION_REQUIRED", "请先完成身份核验")
    s.lock(db)
    user = find_user(db, user_id)
    row = db.scalar(
        select(TrustedIdentity).where(
            TrustedIdentity.user_id == user.id, TrustedIdentity.provider == provider
        )
    )
    if not row:
        raise DomainError("NOT_FOUND", "未找到该平台关联", 404)
    version_check(row, payload.expected_version)
    db.delete(row)
    if provider == "weibo":
        user.weibo_visible = False
    s.revoke(db, user.id)
    s.audit(
        db,
        "identity.admin_unbind",
        actor,
        user.id,
        reason=payload.reason,
        ticket_number=payload.ticket_number,
        provider=provider,
        result="local_unbound",
        provider_revoked=False,
    )
    db.commit()
    return success(
        {
            "local_unbound": True,
            "provider_revoked": False,
            "message": "FanOS 关联已解除，平台侧授权撤销未确认",
        }
    )


class SupportPatch(BaseModel):
    expected_version: int
    enabled: bool
    type: str
    display_name: str = Field(min_length=1, max_length=100)
    url: str | None = None
    contact: str = Field(max_length=500)
    backup: str = Field(max_length=1000)
    reason: str


@router.get("/support-entry")
def support_get(actor=Depends(current_admin), db: Session = Depends(get_db)):
    permit(actor, "auth.support.manage")
    row = s.state(db, "support", "support")
    return success({**support(db)["data"], "version": row.version})


@router.patch("/support-entry")
def support_patch(
    payload: SupportPatch, actor=Depends(current_admin), db: Session = Depends(get_db)
):
    permit(actor, "auth.support.manage")
    reason_check(payload.reason)
    s.lock(db)
    row = s.state(db, "support", "support")
    version_check(row, payload.expected_version)
    if payload.type not in {"help_page", "external"}:
        raise DomainError("INVALID_SUPPORT_TYPE", "客服入口类型不正确")
    if payload.url:
        url = urlparse(payload.url)
        if (
            url.scheme != "https"
            or url.hostname not in get_settings().support_allowed_hosts
            or url.username
            or url.password
            or url.query
            or url.fragment
        ):
            raise DomainError(
                "INVALID_SUPPORT_URL", "只允许已配置域名的 HTTPS 链接，不可携带查询参数"
            )
    if payload.enabled and not (payload.contact.strip() or payload.url):
        raise DomainError("SUPPORT_CHANNEL_REQUIRED", "启用前请提供有效客服渠道")
    s.change_state(row, **payload.model_dump(exclude={"expected_version", "reason"}))
    s.audit(db, "support.configure", actor, reason=payload.reason, enabled=payload.enabled)
    db.commit()
    return success({**support(db)["data"], "version": row.version})
