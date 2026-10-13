import httpx

from worker.jobs.sync_social_posts import MemoryCursorStore, sync_provider
from worker.providers.mock import MockSocialProvider


def test_sync_is_cursor_based_and_api_idempotent() -> None:
    received = []

    def handler(request: httpx.Request) -> httpx.Response:
        received.append(request)
        return httpx.Response(
            200,
            json={
                "code": 0,
                "message": "success",
                "data": {"created": 1, "updated": 0},
            },
        )

    store = MemoryCursorStore()
    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = MockSocialProvider("weibo")
    assert sync_provider(provider, store, client=client) == {"created": 1, "updated": 0}
    assert store.get("fan-os:social-cursor:weibo") == "1"
    assert sync_provider(provider, store, client=client) == {"created": 1, "updated": 0}
    assert store.get("fan-os:social-cursor:weibo") == "2"
    assert len(received) == 2
