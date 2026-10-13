"""Redis boundary reserved for feed cache, rate limits, and chat presence.

Nothing in Phase 1 imports this module, so adding it does not change current
request behavior. Future modules can share key names without coupling business
services to a concrete Redis client.
"""

from __future__ import annotations

import json
from typing import Any, Protocol

from redis import Redis


class CacheBackend(Protocol):
    def get_json(self, key: str) -> dict[str, Any] | list[Any] | None: ...

    def set_json(self, key: str, value: Any, *, ttl_seconds: int) -> None: ...

    def delete(self, *keys: str) -> int: ...


class RedisCache:
    def __init__(self, url: str) -> None:
        self._client = Redis.from_url(url, decode_responses=True)

    def get_json(self, key: str) -> dict[str, Any] | list[Any] | None:
        value = self._client.get(key)
        if value is None:
            return None
        decoded = json.loads(value)
        if not isinstance(decoded, (dict, list)):
            raise ValueError(f"Cache value at {key!r} is not a JSON object or list")
        return decoded

    def set_json(self, key: str, value: Any, *, ttl_seconds: int) -> None:
        self._client.set(key, json.dumps(value, ensure_ascii=False), ex=ttl_seconds)

    def delete(self, *keys: str) -> int:
        return int(self._client.delete(*keys)) if keys else 0


class RedisKeySpace:
    version = "v1"

    @classmethod
    def community_feed(cls, user_id: str) -> str:
        return f"fanos:{cls.version}:community:feed:{user_id}"

    @classmethod
    def community_post(cls, post_id: str) -> str:
        return f"fanos:{cls.version}:community:post:{post_id}"

    @classmethod
    def chat_presence(cls, user_id: str) -> str:
        return f"fanos:{cls.version}:chat:presence:{user_id}"

    @classmethod
    def chat_unread(cls, user_id: str, room_id: str) -> str:
        return f"fanos:{cls.version}:chat:unread:{user_id}:{room_id}"
