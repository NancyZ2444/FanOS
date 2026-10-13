from __future__ import annotations

import logging
import time
from typing import Protocol

import httpx

from worker.config import get_settings
from worker.providers.base import SocialProvider

logger = logging.getLogger(__name__)


class CursorStore(Protocol):
    def get(self, key: str) -> str | None: ...
    def set(self, key: str, value: str) -> None: ...


class MemoryCursorStore:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}

    def get(self, key: str) -> str | None:
        return self.values.get(key)

    def set(self, key: str, value: str) -> None:
        self.values[key] = value


class RedisCursorStore:
    def __init__(self, url: str):
        import redis

        self.client = redis.Redis.from_url(url, decode_responses=True)

    def get(self, key: str) -> str | None:
        return self.client.get(key)

    def set(self, key: str, value: str) -> None:
        self.client.set(key, value)


def sync_provider(
    provider: SocialProvider,
    cursor_store: CursorStore,
    client: httpx.Client | None = None,
    retries: int = 3,
) -> dict[str, int]:
    settings = get_settings()
    cursor_key = f"fan-os:social-cursor:{provider.name}"
    posts, next_cursor = provider.fetch(cursor_store.get(cursor_key))
    if not posts:
        return {"created": 0, "updated": 0}
    owns_client = client is None
    http = client or httpx.Client(timeout=settings.request_timeout_seconds)
    try:
        for attempt in range(retries):
            try:
                response = http.post(
                    f"{settings.api_base_url.rstrip('/')}/admin/worker/social-posts:upsert",
                    headers={"X-Worker-Token": settings.worker_token},
                    json={"items": posts},
                )
                response.raise_for_status()
                result = response.json()["data"]
                if next_cursor is not None:
                    cursor_store.set(cursor_key, next_cursor)
                return {
                    "created": int(result["created"]),
                    "updated": int(result["updated"]),
                }
            except (httpx.HTTPError, KeyError, ValueError):
                if attempt == retries - 1:
                    raise
                time.sleep(2**attempt)
    finally:
        if owns_client:
            http.close()
    return {"created": 0, "updated": 0}
