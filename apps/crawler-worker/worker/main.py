from __future__ import annotations

import logging

from apscheduler.schedulers.blocking import BlockingScheduler

from worker.config import get_settings
from worker.jobs.sync_social_posts import RedisCursorStore, sync_provider
from worker.providers.factory import build_providers

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s"
)
logger = logging.getLogger("fan-os-worker")


def run_once() -> None:
    settings = get_settings()
    cursor_store = RedisCursorStore(settings.redis_url)
    for provider in build_providers():
        try:
            result = sync_provider(provider, cursor_store)
            logger.info(
                "platform=%s created=%s updated=%s",
                provider.name,
                result["created"],
                result["updated"],
            )
        except Exception:
            logger.exception(
                "platform=%s sync failed; other platforms continue", provider.name
            )


def main() -> None:
    settings = get_settings()
    run_once()
    scheduler = BlockingScheduler(timezone="UTC")
    scheduler.add_job(
        run_once,
        "interval",
        minutes=settings.sync_interval_minutes,
        id="sync-social-posts",
        max_instances=1,
        coalesce=True,
    )
    scheduler.start()


if __name__ == "__main__":
    main()
