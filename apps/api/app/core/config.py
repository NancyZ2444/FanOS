from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

API_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = API_ROOT.parents[1]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=API_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "Fan OS API"
    environment: str = "development"
    api_v1_prefix: str = "/api/v1"
    database_url: str = f"sqlite:///{API_ROOT / 'data' / 'fan_os.db'}"
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret: str = "fan-os-development-secret-change-in-production"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 60
    refresh_token_days: int = 30
    dev_phone_code: str = "123456"
    auto_seed: bool = True
    cors_origins: list[str] = Field(default_factory=lambda: ["*"])

    storage_backend: str = "local"
    local_media_root: Path = API_ROOT / "data" / "uploads"
    public_media_base_url: str = "http://localhost:8000/media"
    catalog_image_hosts: list[str] = Field(default_factory=lambda: ["upload.wikimedia.org"])
    catalog_remote_portraits_enabled: bool = False
    catalog_image_user_agent: str = "FanOS-CatalogThumbnail/1.0"
    s3_endpoint_url: str | None = None
    s3_access_key: str | None = None
    s3_secret_key: str | None = None
    s3_bucket: str = "fan-os-media"
    s3_region: str = "us-east-1"
    s3_public_base_url: str | None = None

    card_matcher_index_path: Path = API_ROOT / "data" / "card_matcher" / "cards.json"
    card_matcher_max_candidates: int = 5
    card_detector_max_cards: int = 10
    scan_max_bytes: int = 15 * 1024 * 1024
    scan_max_pixels: int = 24_000_000
    worker_token: str = "fan-os-dev-worker-token"

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.local_media_root.mkdir(parents=True, exist_ok=True)
    settings.card_matcher_index_path.parent.mkdir(parents=True, exist_ok=True)
    return settings
