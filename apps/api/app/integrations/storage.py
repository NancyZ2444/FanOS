from __future__ import annotations

import mimetypes
from abc import ABC, abstractmethod
from pathlib import Path
from urllib.parse import unquote
from uuid import uuid4

from app.core.config import get_settings


class ObjectStorage(ABC):
    @abstractmethod
    def save_bytes(self, content: bytes, filename: str, prefix: str) -> str: ...

    def read_bytes(self, url: str) -> bytes:
        raise NotImplementedError


def _owned_key(url: str, base: str) -> str:
    # Only read our own persisted objects; never fetch a caller-provided URL.
    prefix = base.rstrip("/") + "/"
    if not url.startswith(prefix):
        raise ValueError("Object does not belong to this storage")
    key = unquote(url[len(prefix) :])
    if not key or any(part in {"", ".", ".."} for part in key.split("/")) or "\\" in key:
        raise ValueError("Invalid object key")
    return key


class LocalStorage(ObjectStorage):
    def read_bytes(self, url: str) -> bytes:
        settings = get_settings()
        root = settings.local_media_root.resolve()
        target = (root / _owned_key(url, settings.public_media_base_url)).resolve()
        if not target.is_relative_to(root):
            raise ValueError("Invalid object path")
        return target.read_bytes()

    def save_bytes(self, content: bytes, filename: str, prefix: str) -> str:
        settings = get_settings()
        suffix = Path(filename).suffix.lower() or mimetypes.guess_extension("image/jpeg") or ".jpg"
        key = f"{prefix.strip('/')}/{uuid4().hex}{suffix}"
        target = settings.local_media_root / key
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        return f"{settings.public_media_base_url.rstrip('/')}/{key}"


class S3Storage(ObjectStorage):
    def __init__(self) -> None:
        import boto3

        settings = get_settings()
        self.settings = settings
        self.client = boto3.client(
            "s3",
            endpoint_url=settings.s3_endpoint_url,
            aws_access_key_id=settings.s3_access_key,
            aws_secret_access_key=settings.s3_secret_key,
            region_name=settings.s3_region,
        )

    def read_bytes(self, url: str) -> bytes:
        base = (self.settings.s3_public_base_url or self.settings.s3_endpoint_url or "").rstrip("/")
        key = _owned_key(url, f"{base}/{self.settings.s3_bucket}")
        response = self.client.get_object(Bucket=self.settings.s3_bucket, Key=key)
        with response["Body"] as body:
            return body.read()

    def save_bytes(self, content: bytes, filename: str, prefix: str) -> str:
        suffix = Path(filename).suffix.lower() or ".jpg"
        key = f"{prefix.strip('/')}/{uuid4().hex}{suffix}"
        self.client.put_object(Bucket=self.settings.s3_bucket, Key=key, Body=content)
        endpoint = (self.settings.s3_public_base_url or self.settings.s3_endpoint_url or "").rstrip(
            "/"
        )
        return f"{endpoint}/{self.settings.s3_bucket}/{key}"


def get_storage() -> ObjectStorage:
    return S3Storage() if get_settings().storage_backend == "s3" else LocalStorage()
