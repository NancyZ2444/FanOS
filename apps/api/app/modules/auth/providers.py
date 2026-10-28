"""Fail-closed production provider boundary. Never log codes or platform credentials."""

import hashlib
import hmac
import json
import logging
import time
from contextvars import ContextVar
from datetime import UTC, datetime, timedelta
from urllib.parse import urlsplit

import httpx

from app.common.response import DomainError
from app.core.config import get_settings

_private_request = ContextVar("auth_provider_private_request", default=False)


class _ProviderLogFilter(logging.Filter):
    def filter(self, record):
        # HTTPX's INFO request URL can include OAuth codes, secrets and tokens.
        # Keep observability without exposing request/response details, even if
        # an operator enables transport DEBUG logging. Context-local, not a
        # temporary global logger level that could race concurrent requests.
        if _private_request.get():
            record.msg = "Authentication provider HTTP event (details redacted)"
            record.args = ()
            record.exc_info = None
            record.exc_text = None
            record.stack_info = None
        return True


for _logger in (
    "httpx",
    "httpcore.connection",
    "httpcore.http11",
    "httpcore.http2",
    "httpcore.proxy",
    "httpcore.socks",
):
    logging.getLogger(_logger).addFilter(_ProviderLogFilter())


def _private_http(call, *args, **kwargs):
    token = _private_request.set(True)
    try:
        return call(*args, **kwargs)
    finally:
        _private_request.reset(token)


def sms_available():
    s = get_settings()
    return bool(
        s.sms_enabled
        and all(
            (s.sms_secret_id, s.sms_secret_key, s.sms_app_id, s.sms_template_id, s.sms_sign_name)
        )
    )


def send_sms(phone: str, code: str) -> str:
    # Tencent SendSms API 2021-01-11, TC3-HMAC-SHA256 official signature protocol.
    if not sms_available():
        raise DomainError("SMS_PROVIDER_NOT_CONFIGURED", "短信服务尚未配置，请联系客服", 503)
    s = get_settings()
    timestamp = int(time.time())
    date = datetime.fromtimestamp(timestamp, UTC).strftime("%Y-%m-%d")
    body = json.dumps(
        {
            "PhoneNumberSet": ["+86" + phone],
            "SmsSdkAppId": s.sms_app_id,
            "SignName": s.sms_sign_name,
            "TemplateId": s.sms_template_id,
            "TemplateParamSet": [code],
        },
        separators=(",", ":"),
    )

    def sha(value):
        return hashlib.sha256(value.encode()).hexdigest()

    def sign(key, value):
        return hmac.new(key, value.encode(), hashlib.sha256).digest()

    canonical = (
        "POST\n/\n\ncontent-type:application/json; charset=utf-8\n"
        "host:sms.tencentcloudapi.com\n\ncontent-type;host\n" + sha(body)
    )
    scope = f"{date}/sms/tc3_request"
    to_sign = f"TC3-HMAC-SHA256\n{timestamp}\n{scope}\n{sha(canonical)}"
    key = sign(sign(sign(("TC3" + s.sms_secret_key).encode(), date), "sms"), "tc3_request")
    signature = hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest()
    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "Host": "sms.tencentcloudapi.com",
        "X-TC-Action": "SendSms",
        "X-TC-Version": "2021-01-11",
        "X-TC-Region": s.sms_region,
        "X-TC-Timestamp": str(timestamp),
        "Authorization": (
            f"TC3-HMAC-SHA256 Credential={s.sms_secret_id}/{scope}, "
            f"SignedHeaders=content-type;host, Signature={signature}"
        ),
    }
    try:
        response = _private_http(
            httpx.post,
            "https://sms.tencentcloudapi.com",
            content=body.encode(),
            headers=headers,
            timeout=10,
        )
        payload = response.json()
        data = payload.get("Response", {}) if isinstance(payload, dict) else {}
    except (httpx.HTTPError, ValueError):
        return "unknown"
    if not isinstance(data, dict):
        return "unknown"
    if response.status_code >= 500:
        return "unknown"
    status = data.get("SendStatusSet", [])
    if not isinstance(status, list) or not status:
        return "failed" if isinstance(data.get("Error"), dict) else "unknown"
    if not isinstance(status[0], dict):
        return "unknown"
    if response.status_code == 200 and status[0].get("Code") == "Ok":
        return "accepted"
    return "failed" if status[0].get("Code") else "unknown"


def _https_callback(value: str) -> bool:
    parts = urlsplit(value)
    return bool(
        parts.scheme == "https"
        and parts.hostname
        and not parts.username
        and not parts.password
        and not parts.fragment
        and not parts.query
    )


def oauth_available(provider: str) -> bool:
    s = get_settings()
    if not s.oauth_native_verified:
        return False
    if provider == "wechat":
        return bool(
            s.wechat_enabled
            and s.wechat_app_id
            and s.wechat_app_secret
            and _https_callback(s.wechat_universal_link)
        )
    if provider == "weibo":
        return bool(
            s.weibo_enabled
            and s.weibo_app_key
            and s.weibo_app_secret
            and _https_callback(s.weibo_redirect_uri)
        )
    if provider == "qq":
        return bool(s.qq_enabled and s.qq_app_id and _https_callback(s.qq_universal_link))
    return False


def oauth_parameters(provider: str) -> dict:
    if not oauth_available(provider):
        raise DomainError(
            "OAUTH_PROVIDER_NOT_CONFIGURED", "平台授权尚未完成配置，请使用手机号登录", 503
        )
    s = get_settings()
    if provider == "wechat":
        return {
            "app_id": s.wechat_app_id,
            "scope": "snsapi_userinfo",
            "universal_link": s.wechat_universal_link,
        }
    if provider == "qq":
        return {
            "app_id": s.qq_app_id,
            "scope": "get_user_info",
            "universal_link": s.qq_universal_link,
        }
    return {"app_key": s.weibo_app_key, "redirect_uri": s.weibo_redirect_uri}


def _provider_json(method: str, url: str, **kwargs) -> dict:
    # Fixed upstream endpoints only. Error URLs can contain credentials: never echo.
    try:
        response = _private_http(
            httpx.request, method, url, timeout=10, follow_redirects=False, **kwargs
        )
        if response.status_code >= 500 or response.status_code == 429:
            raise DomainError(
                "OAUTH_TEMPORARILY_UNAVAILABLE", "平台验证暂不可用，请稍后重新授权", 503
            )
        value = response.json()
    except (httpx.HTTPError, ValueError):
        raise DomainError(
            "OAUTH_TEMPORARILY_UNAVAILABLE", "平台验证暂不可用，请稍后重新授权", 503
        ) from None
    if not 200 <= response.status_code < 300 or not isinstance(value, dict):
        raise DomainError("OAUTH_CREDENTIAL_INVALID", "平台授权已失效，请重新授权", 401)
    if value.get("errcode") or value.get("error") or value.get("error_code"):
        raise DomainError("OAUTH_CREDENTIAL_INVALID", "平台授权已失效，请重新授权", 401)
    return value


def _positive(value) -> bool:
    try:
        return float(value) > 0
    except (ValueError, TypeError):
        return False


def _invalid():
    raise DomainError("OAUTH_CREDENTIAL_INVALID", "平台授权无法验证，请重新授权", 401)


def verify_oauth(provider: str, credential_type: str, credential: str) -> dict:
    oauth_parameters(provider)
    if not isinstance(credential, str) or not credential or len(credential) > 4096:
        _invalid()
    s = get_settings()
    if provider == "wechat":
        # Exchange a one-time code with OUR app credentials. Never accept a client UID.
        if credential_type not in {"code", "authorization_code"}:
            _invalid()
        token = _provider_json(
            "GET",
            "https://api.weixin.qq.com/sns/oauth2/access_token",
            params={
                "appid": s.wechat_app_id,
                "secret": s.wechat_app_secret,
                "code": credential,
                "grant_type": "authorization_code",
            },
        )
        subject, access = token.get("openid"), token.get("access_token")
        if (
            not isinstance(subject, str)
            or not subject
            or not access
            or not _positive(token.get("expires_in"))
        ):
            _invalid()
        profile = _provider_json(
            "GET",
            "https://api.weixin.qq.com/sns/userinfo",
            params={"access_token": access, "openid": subject, "lang": "zh_CN"},
        )
        if profile.get("openid") != subject:
            _invalid()
        return {
            "app_scope": s.wechat_app_id,
            "subject": subject,
            "display_name": str(profile.get("nickname") or "")[:180],
            "authorization_status": "valid",
            "authorization_expires_at": (
                datetime.now(UTC) + timedelta(seconds=min(float(token["expires_in"]), 315360000))
            ).isoformat(),
        }
    if provider == "qq":
        # QQ native SDK provides a token, not a trusted openid. Resolve its app
        # ownership + subject server-side; never accept either from the client.
        if credential_type != "access_token":
            _invalid()
        info = _provider_json(
            "GET",
            "https://graph.qq.com/oauth2.0/me",
            params={"access_token": credential, "fmt": "json"},
        )
        subject = info.get("openid")
        if (
            str(info.get("client_id") or "") != s.qq_app_id
            or not isinstance(subject, str)
            or not subject
            or len(subject) > 240
        ):
            _invalid()
        profile = _provider_json(
            "GET",
            "https://graph.qq.com/user/get_user_info",
            params={
                "access_token": credential,
                "oauth_consumer_key": s.qq_app_id,
                "openid": subject,
            },
        )
        if profile.get("ret") != 0:
            _invalid()
        return {
            "app_scope": s.qq_app_id,
            "subject": subject,
            "display_name": str(profile.get("nickname") or "")[:180],
            # These endpoints attest validity now but do not attest a token TTL.
            # Never fabricate a future expiry or persist the OAuth access token.
            "authorization_status": "unknown",
        }
    if credential_type in {"code", "authorization_code"}:
        token = _provider_json(
            "POST",
            "https://api.weibo.com/oauth2/access_token",
            data={
                "client_id": s.weibo_app_key,
                "client_secret": s.weibo_app_secret,
                "grant_type": "authorization_code",
                "redirect_uri": s.weibo_redirect_uri,
                "code": credential,
            },
        )
        access = token.get("access_token")
        if not access:
            _invalid()
    elif credential_type == "access_token":
        access = credential
    else:
        _invalid()
    # Resolve both UID and app ownership upstream; another app's token is invalid.
    info = _provider_json(
        "POST", "https://api.weibo.com/oauth2/get_token_info", data={"access_token": access}
    )
    subject = str(info.get("uid") or "")
    if (
        str(info.get("appkey") or "") != s.weibo_app_key
        or not subject.isdigit()
        or not _positive(info.get("expire_in"))
    ):
        _invalid()
    profile = _provider_json(
        "GET",
        "https://api.weibo.com/2/users/show.json",
        params={"access_token": access, "uid": subject},
    )
    if str(profile.get("idstr") or profile.get("id") or "") != subject:
        _invalid()
    return {
        "app_scope": s.weibo_app_key,
        "subject": subject,
        "display_name": str(profile.get("screen_name") or "")[:180],
        "profile_url": f"https://weibo.com/u/{subject}",
        "authorization_status": "valid",
        "authorization_expires_at": (
            datetime.now(UTC) + timedelta(seconds=min(float(info["expire_in"]), 315360000))
        ).isoformat(),
    }
