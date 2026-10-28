"""Provider contract tests use only mocked HTTP; never send real SMS or tokens."""

import json
import logging

import httpx
import pytest

from app.common.response import DomainError
from app.core.config import get_settings
from app.modules.auth import providers


def enable(monkeypatch, provider):
    settings = get_settings()
    monkeypatch.setattr(settings, "oauth_native_verified", True)
    values = (
        {
            "wechat_enabled": True,
            "wechat_app_id": "wx-test",
            "wechat_app_secret": "test-secret",
            "wechat_universal_link": "https://test.example/wechat/",
        }
        if provider == "wechat"
        else {
            "weibo_enabled": True,
            "weibo_app_key": "12345",
            "weibo_app_secret": "test-secret",
            "weibo_redirect_uri": "https://test.example/weibo/",
        }
    )
    for key, value in values.items():
        monkeypatch.setattr(settings, key, value)


def mock_responses(monkeypatch, values):
    calls = []

    def request(method, url, **kwargs):
        calls.append((method, url, kwargs))
        assert kwargs["follow_redirects"] is False
        return httpx.Response(200, json=values[len(calls) - 1])

    monkeypatch.setattr(providers.httpx, "request", request)
    return calls


def test_oauth_defaults_disabled_and_parameters_never_contain_secret(monkeypatch):
    for provider in ("wechat", "weibo"):
        enable(monkeypatch, provider)
        assert "test-secret" not in json.dumps(providers.oauth_parameters(provider))
        monkeypatch.setattr(get_settings(), "oauth_native_verified", False)
        assert not providers.oauth_available(provider)
        with pytest.raises(DomainError):
            providers.verify_oauth(provider, "code", "test-code")


def test_wechat_uses_app_scoped_server_exchange_and_matching_profile(monkeypatch):
    enable(monkeypatch, "wechat")
    calls = mock_responses(
        monkeypatch,
        [
            {
                "openid": "trusted-openid",
                "access_token": "private-provider-token",
                "expires_in": 7200,
            },
            {"openid": "trusted-openid", "nickname": "真实昵称"},
        ],
    )
    result = providers.verify_oauth("wechat", "code", "one-time-code")
    assert calls[0][2]["params"]["appid"] == "wx-test"
    assert result["subject"] == "trusted-openid" and result["app_scope"] == "wx-test"
    assert "private-provider-token" not in json.dumps(result)
    with pytest.raises(DomainError):
        providers.verify_oauth("wechat", "uid", "arbitrary-client-uid")


@pytest.mark.parametrize(
    "info",
    [
        {"uid": "123", "appkey": "wrong-app", "expire_in": 3600},
        {"uid": "123", "appkey": "12345", "expire_in": 0},
        {"uid": "123", "expire_in": 3600},
    ],
)
def test_weibo_rejects_foreign_unknown_and_expired_token(monkeypatch, info):
    enable(monkeypatch, "weibo")
    calls = mock_responses(monkeypatch, [info])
    with pytest.raises(DomainError):
        providers.verify_oauth("weibo", "access_token", "provider-token")
    assert len(calls) == 1


def test_weibo_resolves_uid_nickname_and_url_only_from_verified_provider(monkeypatch):
    enable(monkeypatch, "weibo")
    mock_responses(
        monkeypatch,
        [
            {"uid": "123", "appkey": "12345", "expire_in": 3600},
            {"idstr": "123", "screen_name": "平台昵称", "profile_url": "https://untrusted.example"},
        ],
    )
    result = providers.verify_oauth("weibo", "access_token", "provider-token")
    assert result["profile_url"] == "https://weibo.com/u/123"
    assert result["display_name"] == "平台昵称"


def test_provider_network_errors_never_echo_credentials(monkeypatch):
    enable(monkeypatch, "wechat")

    def unavailable(*args, **kwargs):
        raise httpx.ConnectError("secret=must-not-echo")

    monkeypatch.setattr(providers.httpx, "request", unavailable)
    with pytest.raises(DomainError) as error:
        providers.verify_oauth("wechat", "code", "test-code")
    assert "must-not-echo" not in str(error.value)
    assert error.value.status_code == 503


def test_http_transport_logging_redacts_credentials(monkeypatch, caplog):
    enable(monkeypatch, "wechat")

    def request(method, url, **kwargs):
        transport = httpx.MockTransport(lambda request: httpx.Response(200, json={}))
        with httpx.Client(transport=transport) as client:
            return client.request(method, url, **kwargs)

    monkeypatch.setattr(providers.httpx, "request", request)
    with caplog.at_level(logging.INFO, logger="httpx"):
        providers._provider_json(
            "GET",
            "https://api.weixin.qq.com/sns/oauth2/access_token",
            params={"secret": "private-secret", "code": "private-code"},
        )
    assert "details redacted" in caplog.text
    assert "private-secret" not in caplog.text and "private-code" not in caplog.text
    assert not providers._private_request.get()


def test_sms_request_and_unknown_delivery_contract(monkeypatch):
    settings = get_settings()
    for name, value in {
        "sms_enabled": True,
        "sms_secret_id": "test-key",
        "sms_secret_key": "test-secret",
        "sms_app_id": "test-app",
        "sms_template_id": "template",
        "sms_sign_name": "测试",
    }.items():
        monkeypatch.setattr(settings, name, value)
    calls = []

    def accepted(url, **kwargs):
        calls.append((url, kwargs))
        return httpx.Response(200, json={"Response": {"SendStatusSet": [{"Code": "Ok"}]}})

    monkeypatch.setattr(providers.httpx, "post", accepted)
    assert providers.send_sms("13800000000", "012345") == "accepted"
    url, request = calls[0]
    assert url == "https://sms.tencentcloudapi.com"
    assert json.loads(request["content"])["TemplateParamSet"] == ["012345"]
    assert request["headers"]["X-TC-Version"] == "2021-01-11"
    assert request["headers"]["Authorization"].startswith("TC3-HMAC-SHA256 ")

    def timeout(*args, **kwargs):
        raise httpx.ReadTimeout("delivery-unknown")

    monkeypatch.setattr(providers.httpx, "post", timeout)
    assert providers.send_sms("13800000000", "012345") == "unknown"
