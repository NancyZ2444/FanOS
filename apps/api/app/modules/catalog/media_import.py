"""Durable catalog image ingestion. Outbox rows retain original URLs and retry state.

Downloads only run in the worker, never in a catalog/import HTTP transaction.
"""

from __future__ import annotations

import io
import ipaddress
import socket
import time
from urllib.parse import urlsplit

import httpx
from PIL import Image, ImageOps
from sqlalchemy import select

from app.admin_models import ContentMetadata
from app.common.events import enqueue_outbox
from app.core.config import get_settings
from app.future_models import OutboxEvent
from app.integrations.storage import get_storage
from app.modules.catalog.images import MAX_BYTES, MAX_PIXELS, _local_path

EVENT = "catalog.media.ingest"
FIELDS = ("image_url", "cover_image", "front_image_url", "back_image_url", "cover")


def owned_image(source: str | None) -> bool:
    if not source:
        return False
    settings = get_settings()
    if settings.storage_backend == "s3":
        base = (settings.s3_public_base_url or settings.s3_endpoint_url or "").rstrip("/")
        return source.startswith(f"{base}/{settings.s3_bucket}/")
    try:
        return _local_path(source) is not None
    except ValueError:
        return False


def public_image(source: str | None) -> str | None:
    if not source or (get_settings().catalog_images_local_only and not owned_image(source)):
        return None
    return source


def queue_images(db, kind: str, entity_id: str, data: dict) -> int:
    """Idempotent per owner/field/source, part of caller's transaction."""
    existing = db.scalars(
        select(OutboxEvent).where(
            OutboxEvent.event_type == EVENT,
            OutboxEvent.aggregate_type == kind,
            OutboxEvent.aggregate_id == entity_id,
        )
    ).all()
    count = 0
    for field in FIELDS:
        source = data.get(field)
        if not isinstance(source, str) or not source.strip():
            continue
        source = source.strip()
        if any(
            e.payload.get("field") == field
            and (
                source == e.payload.get("stored_url")
                or (
                    source == e.payload.get("source_url")
                    and e.payload.get("state") not in {"ready", "superseded"}
                )
            )
            for e in existing
        ):
            continue
        event = enqueue_outbox(
            db,
            event_type=EVENT,
            aggregate_type=kind,
            aggregate_id=entity_id,
            payload={"field": field, "source_url": source, "state": "pending"},
        )
        existing.append(event)
        count += 1
    return count


def target_data(db, kind, entity_id, *, lock=False):
    from app.models import Card
    from app.modules.admin.catalog_extensions import CatalogRecord
    from app.modules.admin.catalog_service import MODELS

    model = Card if kind == "cards" else CatalogRecord if kind == "versions" else MODELS.get(kind)
    if model is None:
        return None, None, {}
    query = select(model).where(model.id == entity_id)
    row = db.scalar(query.with_for_update() if lock else query)
    if row is None or (kind == "versions" and row.kind != "versions"):
        return None, None, {}
    if kind == "versions":
        return row, None, dict(row.data or {})
    data = {f: getattr(row, f) for f in FIELDS if hasattr(row, f)}
    if kind == "cards":
        return row, None, {**(row.admin_data or {}), **data}
    query = select(ContentMetadata).where(
        ContentMetadata.entity_type == kind,
        ContentMetadata.entity_id == entity_id,
    )
    meta = db.scalar(query.with_for_update() if lock else query)
    return row, meta, {**data, **(meta.data if meta else {})}


def apply_image(db, event, stored: str, thumbnail: str) -> bool:
    """Lock and compare after download: never overwrite a newer admin replacement."""
    row, meta, data = target_data(db, event.aggregate_type, event.aggregate_id, lock=True)
    field = event.payload["field"]
    if row is None or data.get(field) != event.payload["source_url"]:
        return False
    if hasattr(row, field):
        setattr(row, field, stored)
    # Thumbnail is bound to its full URL so replacement never serves a stale thumbnail.
    media = {
        **data.get("managed_images", {}),
        field: {
            "url": stored,
            "thumbnail_url": thumbnail,
        },
    }
    if event.aggregate_type == "versions":
        row.data = {**row.data, field: stored, "managed_images": media}
    elif event.aggregate_type == "cards":
        row.admin_data = {**(row.admin_data or {}), "managed_images": media}
        if field != "image_url":
            row.admin_data = {**row.admin_data, field: stored}
        if field == "image_url" and stored != event.payload["source_url"]:
            enqueue_outbox(
                db,
                event_type="catalog.card.image.updated",
                aggregate_type="card",
                aggregate_id=row.id,
                payload={"card_id": row.id, "image_url": stored},
            )
    else:
        if meta is None:
            meta = ContentMetadata(
                entity_type=event.aggregate_type,
                entity_id=row.id,
                status="PUBLISHED",
                operator_id="media-worker",
                data={},
            )
            db.add(meta)
        meta.data = {**meta.data, field: stored, "managed_images": media}
    return True


def managed_thumbnail(data: dict, source: str | None) -> str | None:
    return next(
        (
            public_image(item.get("thumbnail_url"))
            for item in data.get("managed_images", {}).values()
            if item.get("url") == source
        ),
        None,
    )


def validate_remote(source: str) -> None:
    url = urlsplit(source)
    if (
        url.scheme != "https"
        or url.hostname not in get_settings().catalog_image_hosts
        or url.username
        or url.password
        or url.port not in {None, 443}
        or url.fragment
    ):
        raise ValueError("图片来源未获允许：仅支持配置白名单内的 HTTPS 域名")
    addresses = socket.getaddrinfo(url.hostname, 443, type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
        raise ValueError("图片来源不能指向内网或保留地址")


def download_image(source: str) -> bytes:
    if owned_image(source):
        local = _local_path(source) if get_settings().storage_backend == "local" else None
        if local:
            if local.stat().st_size > MAX_BYTES:
                raise ValueError("图片超过 20 MB")
            return local.read_bytes()
        content = get_storage().read_bytes(source)
        if len(content) > MAX_BYTES:
            raise ValueError("图片超过 20 MB")
        return content
    validate_remote(source)
    started = time.monotonic()
    with httpx.stream(
        "GET",
        source,
        timeout=httpx.Timeout(30, connect=5),
        follow_redirects=False,
        trust_env=False,
        headers={"User-Agent": get_settings().catalog_image_user_agent},
    ) as response:
        response.raise_for_status()
        if response.is_redirect or not response.headers.get("content-type", "").startswith(
            "image/"
        ):
            raise ValueError("外链不是图片或返回重定向，请使用最终图片地址")
        content = bytearray()
        for chunk in response.iter_bytes(chunk_size=65536):
            content.extend(chunk)
            if len(content) > MAX_BYTES or time.monotonic() - started > 45:
                raise ValueError("图片超过大小或下载时限")
        return bytes(content)


def store_image(source: str) -> tuple[str, str]:
    return store_image_bytes(source, download_image(source))


def store_image_bytes(source: str, content: bytes) -> tuple[str, str]:
    """Same bounded conversion for worker downloads and verified offline transfers."""
    if len(content) > MAX_BYTES:
        raise ValueError("图片超过 20 MB")
    with Image.open(io.BytesIO(content)) as original:
        if original.width * original.height > MAX_PIXELS:
            raise ValueError("图片像素尺寸过大")
        if original.format not in {"JPEG", "PNG", "WEBP", "GIF"}:
            raise ValueError("只支持 JPEG、PNG、WebP、GIF 图片")
        image = ImageOps.exif_transpose(original).convert("RGBA")
        image.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
        full = io.BytesIO()
        image.save(full, format="WEBP", quality=90)
        image.thumbnail((384, 384), Image.Resampling.LANCZOS)
        small = io.BytesIO()
        image.save(small, format="WEBP", quality=82)
    storage = get_storage()
    stored = (
        source
        if owned_image(source)
        else storage.save_bytes(full.getvalue(), "image.webp", "catalog-managed")
    )
    thumb = storage.save_bytes(small.getvalue(), "thumbnail.webp", "catalog-managed/thumbs")
    return stored, thumb


def backfill(db) -> int:
    from app.models import Card
    from app.modules.admin.catalog_extensions import CatalogRecord
    from app.modules.admin.catalog_service import MODELS

    count = 0
    for kind, model in {**MODELS, "cards": Card, "versions": CatalogRecord}.items():
        query = select(model)
        if kind == "versions":
            query = query.where(CatalogRecord.kind == "versions")
        for row in db.scalars(query):
            _, _, data = target_data(db, kind, row.id)
            count += queue_images(db, kind, row.id, data)
    db.flush()
    return count
