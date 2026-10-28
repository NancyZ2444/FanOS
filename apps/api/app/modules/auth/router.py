from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth_models import AuthSession, AuthState, TrustedIdentity
from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_user, optional_user, recovery_user
from app.models import User
from app.modules.auth import providers
from app.modules.auth import service as s

router = APIRouter(tags=["Auth"])


class ChallengeRequest(BaseModel):
    phone: str
    purpose: str = "login"


class CodeRequest(BaseModel):
    challenge_id: str
    code: str = Field(min_length=6, max_length=6)


class LoginRequest(BaseModel):
    method: str = "phone"
    phone: str | None = None
    code: str | None = None
    challenge_id: str | None = None
    password: str | None = Field(default=None, max_length=256)


class RefreshRequest(BaseModel):
    refresh_token: str


@router.get("/auth/capabilities")
def capabilities():
    return success(
        {
            "sms_available": providers.sms_available(),
            "wechat_available": providers.oauth_available("wechat"),
            "weibo_available": providers.oauth_available("weibo"),
            "qq_available": providers.oauth_available("qq"),
        }
    )


@router.post("/auth/request-code")
@router.post("/auth/sms/challenges")
def request_code(
    payload: ChallengeRequest,
    request: Request,
    user: User | None = Depends(optional_user),
    db: Session = Depends(get_db),
):
    return success(
        s.request_code(
            db,
            payload.phone,
            payload.purpose,
            user,
            request.client.host if request.client else "",
            request.headers.get("X-Device-ID", "")[:128],
            request.headers.get("Idempotency-Key"),
        )
    )


@router.post("/auth/login")
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)):
    return success(
        s.login(
            db,
            **payload.model_dump(),
            idempotency_key=request.headers.get("Idempotency-Key"),
            ip=request.client.host if request.client else "",
        )
    )


@router.post("/auth/refresh")
def refresh(payload: RefreshRequest, request: Request, db: Session = Depends(get_db)):
    return success(
        s.refresh(db, payload.refresh_token, idempotency_key=request.headers.get("Idempotency-Key"))
    )


@router.post("/auth/logout")
def logout(user: User = Depends(current_user), db: Session = Depends(get_db)):
    s.lock(db)
    db.get(AuthSession, user._auth_session_id).revoked = True
    db.commit()
    return success(message="已退出登录")


@router.post("/auth/verification-tickets")
def verification(
    payload: CodeRequest,
    request: Request,
    user: User | None = Depends(optional_user),
    db: Session = Depends(get_db),
):
    return success(
        s.create_ticket(
            db, payload.challenge_id, payload.code, user, request.headers.get("Idempotency-Key")
        )
    )


def identity_payload(row, provider=None):
    authorization_status = row.authorization_status if row else "unknown"
    if authorization_status == "valid":
        if not row.authorization_expires_at:
            authorization_status = "unknown"
        elif s.aware(row.authorization_expires_at) <= s.now():
            authorization_status = "expired"
    return {
        "provider": row.provider if row else provider,
        "bound": bool(row),
        "subject_masked": s.mask(row.subject) if row else None,
        "app_scope": row.app_scope if row else None,
        "display_name": row.display_name if row else None,
        "profile_url": row.profile_url if row else None,
        "authorization_status": authorization_status,
        "bound_at": row.created_at if row else None,
        "updated_at": row.updated_at if row else None,
        "version": row.version if row else None,
    }


@router.get("/account/identities")
def identities(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = {
        r.provider: r
        for r in db.scalars(select(TrustedIdentity).where(TrustedIdentity.user_id == user.id))
    }
    return success(
        {
            "phone_masked": s.mask(user.phone),
            "identities": [identity_payload(rows.get(p), p) for p in ("wechat", "weibo", "qq")],
            "onboarding_completed": s.user_payload(user, db)["onboarding_completed"],
            "password_setup_required": s.user_payload(user, db)["password_setup_required"],
        }
    )


@router.post("/account/onboarding/complete")
def onboarding(user: User = Depends(current_user), db: Session = Depends(get_db)):
    s.lock(db)
    if s.user_payload(user, db)["password_setup_required"]:
        raise DomainError("PASSWORD_SETUP_REQUIRED", "请先设置登录密码", 409)
    s.change_state(s.state(db, "user:" + user.id), onboarding_completed=True)
    db.commit()
    return success({"onboarding_completed": True})


class InitialPasswordRequest(BaseModel):
    password: str = Field(min_length=1, max_length=256)


@router.post("/account/password")
def initial_password(
    payload: InitialPasswordRequest,
    request: Request,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    return success(
        s.set_initial_password(db, user, payload.password, request.headers.get("Idempotency-Key"))
    )


class UnbindRequest(BaseModel):
    verification_ticket: str
    expected_version: int


@router.post("/account/identities/{provider}/unbind")
def unbind(
    provider: str,
    payload: UnbindRequest,
    request: Request,
    user: User = Depends(recovery_user),
    db: Session = Depends(get_db),
):
    s.lock(db, allow_recovery=True)
    key = request.headers.get("Idempotency-Key")
    cached = s.cached_result(db, "unbind:" + provider, key, payload.model_dump(), user)
    if cached is not None:
        return success(cached)
    s.require_active_session(db, user)
    s.ticket(db, payload.verification_ticket, "unbind_identity", user)
    row = db.scalar(
        select(TrustedIdentity).where(
            TrustedIdentity.user_id == user.id, TrustedIdentity.provider == provider
        )
    )
    if not row or row.version != payload.expected_version:
        raise DomainError("VERSION_CONFLICT", "绑定状态已变化，请刷新", 409)
    s.audit(
        db,
        "identity.unbind",
        actor=user,
        user_id=user.id,
        provider=provider,
        result="local_unbound",
    )
    db.delete(row)
    if provider == "weibo":
        user.weibo_visible = False
    s.revoke(db, user.id)
    result = {
        **s.issue_tokens(user, db),
        "local_unbound": True,
        "provider_revoked": False,
        "message": "已解除 FanOS 关联；平台授权撤销尚未确认，请在平台管理授权",
    }
    s.remember_result(db, "unbind:" + provider, key, payload.model_dump(), result, user)
    db.commit()
    return success(result)


class ChangePhone(BaseModel):
    old_verification_ticket: str
    new_verification_ticket: str


@router.post("/account/change-phone")
def change_phone(
    payload: ChangePhone,
    request: Request,
    user: User = Depends(recovery_user),
    db: Session = Depends(get_db),
):
    s.lock(db, allow_recovery=True)
    key = request.headers.get("Idempotency-Key")
    cached = s.cached_result(db, "change-phone", key, payload.model_dump(), user)
    if cached is not None:
        return success(cached)
    s.require_active_session(db, user)
    old = s.ticket(db, payload.old_verification_ticket, "change_phone_old", user)
    new = s.ticket(db, payload.new_verification_ticket, "change_phone_new", user)
    if old.data["phone"] != user.phone:
        raise DomainError("PHONE_MISMATCH", "原手机号已变化，请重新验证", 409)
    other = db.scalar(select(User).where(User.phone == new.data["phone"]))
    if other:
        raise DomainError("PHONE_ALREADY_BOUND", "新手机号已关联账号，不能覆盖", 409)
    wl = s.whitelist(db, user.phone)
    if wl:
        wl.enabled = False
        wl.version += 1
    user.phone = new.data["phone"]
    s.revoke(db, user.id)
    s.audit(db, "phone.change", user, user.id, result="success")
    result = s.issue_tokens(user, db)
    s.remember_result(db, "change-phone", key, payload.model_dump(), result, user)
    db.commit()
    return success(result)


class OAuthTransaction(BaseModel):
    provider: str
    intent: str
    verification_ticket: str | None = None


@router.post("/auth/oauth/transactions")
def oauth_transaction(
    payload: OAuthTransaction,
    request: Request,
    user: User | None = Depends(optional_user),
    db: Session = Depends(get_db),
):
    if payload.provider not in {"wechat", "weibo", "qq"} or payload.intent not in {"login", "bind"}:
        raise DomainError("INVALID_OAUTH_REQUEST", "不支持的授权操作")
    s.lock(db)
    key = request.headers.get("Idempotency-Key")
    cached = s.cached_result(db, "oauth-transaction", key, payload.model_dump(), user)
    if cached is not None:
        return success(cached)
    if payload.intent == "bind":
        if not user:
            raise DomainError("AUTH_REQUIRED", "请先登录", 401)
        s.ticket(db, payload.verification_ticket, "bind_identity", user)
    params = providers.oauth_parameters(
        payload.provider
    )  # fail closed until audited adapter configured
    import secrets
    from datetime import timedelta

    token, oauth_state = (
        s.digest("oauth-transaction:" + key) if key else secrets.token_urlsafe(32),
        secrets.token_urlsafe(32),
    )
    row = s.state(db, "oauth:" + s.digest(token), "oauth")
    s.change_state(
        row,
        provider=payload.provider,
        intent=payload.intent,
        user_id=getattr(user, "id", None),
        session_id=getattr(user, "_auth_session_id", None),
        state=oauth_state,
        expires_at=(s.now() + timedelta(minutes=5)).isoformat(),
        consumed=False,
    )
    result = {
        "transaction_id": token,
        "state": oauth_state,
        "expires_in": 300,
        "sdk_parameters": params,
    }
    s.remember_result(db, "oauth-transaction", key, payload.model_dump(), result, user)
    db.commit()
    return success(result)


class OAuthComplete(BaseModel):
    transaction_id: str
    state: str
    credential_type: str
    credential: str = Field(min_length=1, max_length=4096)


def oauth_record(db, token):
    from datetime import datetime

    row = db.get(AuthState, "oauth:" + s.digest(token))
    if (
        not row
        or row.data.get("consumed")
        or datetime.fromisoformat(row.data["expires_at"]) <= s.now()
    ):
        raise DomainError("OAUTH_EXPIRED", "授权事务已失效")
    return row


def bind_identity(db, user, identity):
    from datetime import datetime

    expiry = identity.get("authorization_expires_at")
    if isinstance(expiry, str):
        expiry = datetime.fromisoformat(expiry)
    existing = db.scalar(
        select(TrustedIdentity).where(
            TrustedIdentity.provider == identity["provider"],
            TrustedIdentity.app_scope == identity["app_scope"],
            TrustedIdentity.subject == identity["subject"],
        )
    )
    if existing and existing.user_id != user.id:
        raise DomainError("IDENTITY_BOUND_TO_OTHER_USER", "该平台身份已关联其他账号", 409)
    own = db.scalar(
        select(TrustedIdentity).where(
            TrustedIdentity.user_id == user.id, TrustedIdentity.provider == identity["provider"]
        )
    )
    if own and (own.subject != identity["subject"] or own.app_scope != identity["app_scope"]):
        raise DomainError("PROVIDER_ALREADY_BOUND", "当前账号已关联另一平台身份", 409)
    if existing:
        existing.authorization_status = identity.get("authorization_status", "unknown")
        existing.authorization_expires_at = expiry
        existing.display_name = identity.get("display_name", existing.display_name)
        existing.profile_url = identity.get("profile_url")
        existing.version += 1
        return existing
    row = TrustedIdentity(
        user_id=user.id,
        **{
            key: identity[key]
            for key in ("provider", "app_scope", "subject", "display_name", "authorization_status")
        },
    )
    db.add(row)
    row.authorization_expires_at = expiry
    row.profile_url = identity.get("profile_url")
    db.flush()
    if row.provider == "weibo":
        user.weibo_visible = False
    return row


@router.post("/auth/oauth/complete")
def oauth_complete(
    payload: OAuthComplete,
    request: Request,
    user: User | None = Depends(optional_user),
    db: Session = Depends(get_db),
):
    import secrets

    s.lock(db)
    key = request.headers.get("Idempotency-Key")
    cached = s.cached_result(db, "oauth-complete", key, payload.model_dump(), user)
    if cached is not None:
        return success(cached)
    row = oauth_record(db, payload.transaction_id)
    data = row.data
    if not secrets.compare_digest(data["state"], payload.state):
        raise DomainError("OAUTH_STATE_MISMATCH", "授权关联不匹配")
    if data.get("user_id") != getattr(user, "id", None) or data.get("session_id") != getattr(
        user, "_auth_session_id", None
    ):
        raise DomainError("OAUTH_STATE_MISMATCH", "授权账号不匹配")
    identity = providers.verify_oauth(data["provider"], payload.credential_type, payload.credential)
    # Provider adapter must return trusted app-scoped identity, never client UID.
    identity["provider"] = data["provider"]
    if data["intent"] == "bind":
        bound = bind_identity(db, user, identity)
        s.change_state(row, consumed=True)
        s.audit(db, "identity.bind", user, user.id, provider=data["provider"])
        result = {"status": "BOUND", "identity": identity_payload(bound)}
        s.remember_result(db, "oauth-complete", key, payload.model_dump(), result, user)
        db.commit()
        return success(result)
    linked = db.scalar(
        select(TrustedIdentity).where(
            TrustedIdentity.provider == identity["provider"],
            TrustedIdentity.app_scope == identity["app_scope"],
            TrustedIdentity.subject == identity["subject"],
        )
    )
    if linked:
        owner = db.get(User, linked.user_id)
        if owner and owner.phone:
            s.account_available(db, owner)
            bind_identity(db, owner, identity)
            s.change_state(row, consumed=True)
            result = s.issue_tokens(owner, db)
            s.change_state(
                s.state(db, "user:" + owner.id),
                last_login_at=s.now().isoformat(),
                last_login_channel=identity["provider"],
            )
            s.audit(
                db,
                "login.success",
                user_id=owner.id,
                channel=identity["provider"],
                method="oauth",
                result="success",
            )
            result = {"status": "LOGIN_SUCCESS", **result, "is_new_user": False}
            s.remember_result(db, "oauth-complete", key, payload.model_dump(), result, user)
            db.commit()
            return success(result)
    continuation = s.digest("continuation:" + payload.transaction_id)
    s.change_state(row, consumed=True)
    continuation_row = s.state(db, "continuation:" + s.digest(continuation), "continuation")
    s.change_state(
        continuation_row,
        identity=identity,
        expires_at=data["expires_at"],
        consumed=False,
        linked_user_id=linked.user_id if linked else None,
    )
    result = {"status": "PHONE_REQUIRED", "continuation_token": continuation, "expires_in": 300}
    s.remember_result(db, "oauth-complete", key, payload.model_dump(), result, user)
    db.commit()
    return success(result)


class CompletePhone(BaseModel):
    continuation_token: str
    verification_ticket: str
    confirm_link: bool = False


def pending_phone(db, payload):
    from datetime import datetime

    row = db.get(AuthState, "continuation:" + s.digest(payload.continuation_token))
    if (
        not row
        or row.data.get("consumed")
        or datetime.fromisoformat(row.data["expires_at"]) <= s.now()
    ):
        raise DomainError("OAUTH_EXPIRED", "手机号关联已失效")
    verified = s.ticket(db, payload.verification_ticket, "complete_phone", consume=False)
    return row, verified


@router.post("/auth/oauth/preview-phone")
def preview_phone(payload: CompletePhone, db: Session = Depends(get_db)):
    row, verified = pending_phone(db, payload)
    user = db.scalar(select(User).where(User.phone == verified.data["phone"]))
    if row.data.get("linked_user_id"):
        if user and user.id != row.data["linked_user_id"]:
            raise DomainError(
                "IDENTITY_BOUND_TO_OTHER_USER", "手机号与原平台账号冲突，请进入账号恢复流程", 409
            )
        user = db.get(User, row.data["linked_user_id"])
    if user and user.phone:
        s.account_available(db, user)
    return success(
        {
            "display_name": user.display_name if user else "新 FanOS 账号",
            "phone_masked": s.mask(verified.data["phone"]),
            "is_existing": bool(user),
        }
    )


@router.post("/auth/oauth/complete-phone")
def complete_phone(payload: CompletePhone, request: Request, db: Session = Depends(get_db)):
    if not payload.confirm_link:
        raise DomainError("CONFIRMATION_REQUIRED", "请确认关联账号")
    s.lock(db)
    key = request.headers.get("Idempotency-Key")
    cached = s.cached_result(db, "complete-phone", key, payload.model_dump())
    if cached is not None:
        return success(cached)
    row, verified = pending_phone(db, payload)
    if row.data.get("linked_user_id"):
        user = db.get(User, row.data["linked_user_id"])
        existing = db.scalar(select(User).where(User.phone == verified.data["phone"]))
        if not user or (existing and existing.id != user.id):
            raise DomainError(
                "IDENTITY_BOUND_TO_OTHER_USER", "手机号与原平台账号冲突，请进入账号恢复流程", 409
            )
        if user.phone and user.phone != verified.data["phone"]:
            raise DomainError("PHONE_ALREADY_BOUND", "原账号手机号已变化，请重新授权", 409)
        user.phone = verified.data["phone"]
        s.account_available(db, user)
        is_new = False
    else:
        user, is_new = s.get_or_create_user(db, verified.data["phone"])
    bind_identity(db, user, row.data["identity"])
    s.change_state(verified, consumed=True)
    s.change_state(row, consumed=True)
    if verified.data.get("mode") == "test_code":
        s.whitelist(db, verified.data["phone"]).last_login_at = s.now()
    s.change_state(
        s.state(db, "user:" + user.id),
        last_login_at=s.now().isoformat(),
        last_login_channel=row.data["identity"]["provider"],
    )
    s.audit(
        db,
        "login.success",
        user_id=user.id,
        channel=row.data["identity"]["provider"],
        method="oauth_phone",
        result="success",
    )
    result = {**s.issue_tokens(user, db), "is_new_user": is_new}
    s.remember_result(db, "complete-phone", key, payload.model_dump(), result)
    db.commit()
    return success(result)


def support(db: Session = Depends(get_db)):
    row = db.get(AuthState, "support")
    data = row.data if row else {}
    # Only explicitly configured public channels; never invent a support identity.
    return success(
        {
            "id": "login-support",
            "enabled": bool(data.get("enabled")),
            "type": data.get("type", "help_page"),
            "display_name": data.get("display_name", "登录帮助"),
            "url": data.get("url"),
            "contact": data.get("contact", ""),
            "backup": data.get("backup", "客服渠道暂未配置，请稍后重试。"),
        }
    )


@router.get("/auth/support-entry")
def public_support(request: Request, db: Session = Depends(get_db)):
    from datetime import datetime, timedelta

    s.lock(db)
    row = s.state(
        db, "support-rate:" + s.digest(request.client.host if request.client else ""), "rate-limit"
    )
    start = row.data.get("window")
    count = (
        row.data.get("count", 0)
        if start and datetime.fromisoformat(start) > s.now() - timedelta(minutes=1)
        else 0
    )
    if count >= 60:
        raise DomainError("RATE_LIMITED", "请求较多，请稍后重试", 429)
    s.change_state(row, count=count + 1, window=start if count else s.now().isoformat())
    result = support(db)
    db.commit()
    return result
