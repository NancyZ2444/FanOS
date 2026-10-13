from worker.config import get_settings
from worker.providers.base import SocialProvider
from worker.providers.mock import MockSocialProvider

PLATFORMS = ("weibo", "instagram", "x", "xiaohongshu", "douyin")


def build_providers() -> list[SocialProvider]:
    settings = get_settings()
    if settings.social_provider_mode != "mock":
        raise RuntimeError(
            "Real social credentials are not configured. Set SOCIAL_PROVIDER_MODE=mock "
            "or implement the authorized provider adapters."
        )
    return [MockSocialProvider(platform) for platform in PLATFORMS]
