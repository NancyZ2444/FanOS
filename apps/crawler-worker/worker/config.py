from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class WorkerSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    api_base_url: str = "http://localhost:8000/api/v1"
    redis_url: str = "redis://localhost:6379/0"
    worker_token: str = "fan-os-dev-worker-token"
    social_provider_mode: str = "mock"
    sync_interval_minutes: int = 15
    request_timeout_seconds: float = 20


@lru_cache
def get_settings() -> WorkerSettings:
    return WorkerSettings()
