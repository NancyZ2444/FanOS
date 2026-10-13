"""Cached, bounded thumbnails for published catalog portraits (never an open proxy)."""

from __future__ import annotations

import hashlib
import io
import threading
from pathlib import Path
from urllib.parse import unquote, urlsplit

import httpx
from PIL import Image, ImageOps

from app.core.config import get_settings

_locks = [threading.Lock() for _ in range(64)]
MAX_BYTES = 20 * 1024 * 1024
MAX_PIXELS = 40_000_000


def _local_path(source: str) -> Path | None:
    settings = get_settings()
    url = urlsplit(source)
    base = urlsplit(settings.public_media_base_url)
    own_host = url.netloc == base.netloc or url.hostname in {"localhost", "127.0.0.1", "::1"}
    prefix = base.path.rstrip("/") + "/"
    if not own_host or not url.path.startswith(prefix):
        return None
    root = settings.local_media_root.resolve()
    path = (root / unquote(url.path[len(prefix) :])).resolve()
    if not path.is_relative_to(root):
        raise ValueError("Invalid media path")
    return path


def image_version(source: str) -> str:
    local = _local_path(source)
    revision = str(local.stat().st_mtime_ns) if local and local.is_file() else ""
    return hashlib.sha256(f"v1:{source}:{revision}".encode()).hexdigest()[:24]


def thumbnail_url(kind: str, entity_id: str, source: str | None) -> str | None:
    if not source:
        return None
    if (
        not _local_path(source)
        and urlsplit(source).hostname not in get_settings().catalog_image_hosts
    ):
        return None
    if not _local_path(source) and not get_settings().catalog_remote_portraits_enabled:
        cached = (
            get_settings().local_media_root / "catalog-thumbnails" / f"{image_version(source)}.webp"
        )
        if not cached.is_file():
            # Preserve the original URL until this origin is ready for server caching.
            return None
    prefix = get_settings().api_v1_prefix
    return f"{prefix}/catalog/images/{kind}/{entity_id}?v={image_version(source)}"


def remote_thumbnail_source(source: str) -> str:
    url = urlsplit(source)
    # Wikimedia requires standard widths. Request the 500px derivative instead
    # of multi-megabyte originals: https://www.mediawiki.org/wiki/Common_thumbnail_sizes
    prefix = "/wikipedia/commons/"
    if url.hostname == "upload.wikimedia.org" and url.path.startswith(prefix):
        tail = url.path[len(prefix) :]
        if not tail.startswith("thumb/") and tail.lower().endswith(
            (".jpg", ".jpeg", ".png", ".webp")
        ):
            filename = tail.rsplit("/", 1)[-1]
            return url._replace(path=f"{prefix}thumb/{tail}/500px-{filename}").geturl()
    return source


def _source_bytes(source: str) -> bytes:
    local = _local_path(source)
    if local:
        if local.stat().st_size > MAX_BYTES:
            raise ValueError("Image is too large")
        return local.read_bytes()
    if not get_settings().catalog_remote_portraits_enabled:
        raise ValueError("Remote portrait downloads are disabled")
    url = urlsplit(source)
    # Remote domains must be explicitly trusted; no redirects or arbitrary URL input.
    if (
        url.scheme != "https"
        or url.hostname not in get_settings().catalog_image_hosts
        or url.username
        or url.password
        or url.port not in {None, 443}
    ):
        raise ValueError("Unsupported image origin")
    with httpx.stream(
        "GET",
        remote_thumbnail_source(source),
        timeout=httpx.Timeout(20, connect=5),
        follow_redirects=False,
        headers={"User-Agent": get_settings().catalog_image_user_agent},
    ) as response:
        response.raise_for_status()
        content = bytearray()
        for chunk in response.iter_bytes():
            content.extend(chunk)
            if len(content) > MAX_BYTES:
                raise ValueError("Image is too large")
        return bytes(content)


def cached_thumbnail(source: str) -> Path:
    key = image_version(source)
    target = get_settings().local_media_root / "catalog-thumbnails" / f"{key}.webp"
    with _locks[int(key[:2], 16) % len(_locks)]:
        if target.is_file():
            return target
        content = _source_bytes(source)
        with Image.open(io.BytesIO(content)) as image:
            if image.width * image.height > MAX_PIXELS:
                raise ValueError("Image dimensions are too large")
            image = ImageOps.exif_transpose(image)
            image.thumbnail((384, 384), Image.Resampling.LANCZOS)
            image = image.convert("RGB")
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix(f".{threading.get_ident()}.tmp")
            try:
                image.save(temporary, format="WEBP", quality=82)
                temporary.replace(target)
            finally:
                temporary.unlink(missing_ok=True)
    return target
