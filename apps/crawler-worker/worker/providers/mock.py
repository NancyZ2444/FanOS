from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from worker.providers.base import SocialProvider


class MockSocialProvider(SocialProvider):
    def __init__(self, name: str):
        self.name = name

    def fetch(
        self, cursor: str | None = None
    ) -> tuple[list[dict[str, Any]], str | None]:
        sequence = int(cursor or 0) + 1
        now = datetime.now(UTC).isoformat()
        return (
            [
                {
                    "platform": self.name,
                    "original_post_id": f"mock-{self.name}-{sequence}",
                    "author_type": "idol",
                    "idol_id": "idol-aria",
                    "group_id": "group-lumina",
                    "post_time": now,
                    "content": f"{self.name} 同步演示动态 #{sequence}",
                    "media": [],
                    "original_url": _url(self.name),
                    "fetch_time": now,
                    "is_available": True,
                }
            ],
            str(sequence),
        )


def _url(platform: str) -> str:
    return {
        "weibo": "https://weibo.com",
        "instagram": "https://instagram.com",
        "x": "https://x.com",
        "xiaohongshu": "https://xiaohongshu.com",
        "douyin": "https://douyin.com",
    }[platform]
