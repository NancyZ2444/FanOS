from __future__ import annotations

from collections.abc import Callable
from typing import Any

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import FileResponse, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.response import DomainError, success
from app.common.serializers import card_payload, profile_payload
from app.core.database import get_db
from app.core.security import optional_user
from app.models import User
from app.modules.catalog.service import bootstrap

router = APIRouter(prefix="/catalog", tags=["Catalog"])


@router.get("/images/{kind}/{entity_id}")
def catalog_thumbnail(kind: str, entity_id: str, request: Request, db: Session = Depends(get_db)):
    from app.admin_models import ContentMetadata
    from app.modules.catalog.images import cached_thumbnail, image_version, portrait_source

    if kind not in {"groups", "idols"}:
        raise DomainError("IMAGE_NOT_FOUND", "图片不存在", 404)
    row = db.scalar(
        select(ContentMetadata).where(
            ContentMetadata.entity_type == kind,
            ContentMetadata.entity_id == entity_id,
            ContentMetadata.status == "PUBLISHED",
        )
    )
    source = portrait_source(row.data or {}) if row else None
    if not source:
        raise DomainError("IMAGE_NOT_FOUND", "图片不存在或未公开", 404)
    try:
        path = cached_thumbnail(source)
        etag = f'"{image_version(source)}"'
    except Exception as exc:
        raise DomainError("IMAGE_UNAVAILABLE", "头像暂时无法加载", 503) from exc
    headers = {"Cache-Control": "public, max-age=86400", "ETag": etag}
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)
    return FileResponse(path, media_type="image/webp", headers=headers)


def _contains(item: dict[str, Any], query: str | None, fields: tuple[str, ...]) -> bool:
    if not query:
        return True
    needle = query.casefold()
    return any(needle in str(item.get(field, "")).casefold() for field in fields)


def _page(
    items: list[dict[str, Any]],
    cursor: int,
    limit: int,
    key: Callable[[dict[str, Any]], Any],
    reverse: bool = False,
) -> dict[str, object]:
    ordered = sorted(items, key=key, reverse=reverse)
    page = ordered[cursor : cursor + limit]
    next_offset = cursor + len(page)
    return {
        "items": page,
        "total": len(ordered),
        "next_cursor": str(next_offset) if next_offset < len(ordered) else None,
    }


def _tagged_page(items, tags, cursor, limit, key, reverse=False):
    # Aggregate the complete filtered result set, before pagination, including
    # selected tags. A changed context never leaks unrelated global tags.
    selected = set(tags or [])
    filtered = [item for item in items if selected.issubset(set(item.get("tag_ids", [])))]
    facets = {}
    for item in filtered:
        for tag in item.get("tag_details", []):
            if tag["id"] not in facets:
                facets[tag["id"]] = {**tag, "usage_count": 0}
            facets[tag["id"]]["usage_count"] += 1
    return {
        **_page(filtered, cursor, limit, key, reverse),
        "available_tags": sorted(facets.values(), key=lambda t: (t["name"].casefold(), t["id"])),
    }


def _name_key(item: dict[str, Any]) -> str:
    return str(item.get("name", ""))


def _title_key(item: dict[str, Any]) -> str:
    return str(item.get("title", ""))


def _release_key(item: dict[str, Any]) -> tuple[str, str]:
    return str(item.get("release_date", "")), str(item.get("id", ""))


def _entity(data: dict[str, list[dict[str, object]]], kind: str, entity_id: str) -> dict:
    item = next((entry for entry in data[kind] if entry["id"] == entity_id), None)
    if item is None:
        raise DomainError("CATALOG_ENTITY_NOT_FOUND", "图鉴资料不存在或已停止公开", 404)
    return item


@router.get("/bootstrap")
def get_bootstrap(db: Session = Depends(get_db)) -> dict:
    return success(bootstrap(db))


@router.get("/collections")
def list_collections(db: Session = Depends(get_db)) -> dict:
    items = bootstrap(db)["others"]
    return success({"items": items, "total": len(items)})


@router.get("/collections/{entity_id}")
def collection_detail(entity_id: str, db: Session = Depends(get_db)) -> dict:
    return success(_entity(bootstrap(db), "others", entity_id))


@router.get("/groups")
def list_groups(
    q: str | None = Query(default=None, max_length=80),
    status: str | None = None,
    sort: str = Query(default="az", pattern="^(az|za)$"),
    cursor: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
) -> dict:
    items = [
        item
        for item in bootstrap(db)["groups"]
        if _contains(item, q, ("name", "name_en", "name_ko", "name_translated", "company"))
        and (not status or item["status"] == status)
    ]
    return success(_page(items, cursor, limit, _name_key, reverse=sort == "za"))


@router.get("/idols")
def list_idols(
    q: str | None = Query(default=None, max_length=80),
    group_id: str | None = None,
    region: str | None = None,
    cursor: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
) -> dict:
    data = bootstrap(db)
    items = [
        item
        for item in data["idols"]
        if _contains(
            item,
            q,
            ("name", "name_en", "name_ko", "name_translated", "group_name", "company", "role"),
        )
        and (not group_id or group_id in item["group_ids"])
        and (not region or item["region"] == region)
    ]
    return success(_page(items, cursor, limit, lambda item: item["name"]))


@router.get("/albums")
def list_albums(
    q: str | None = Query(default=None, max_length=80),
    group_id: str | None = None,
    idol_id: str | None = None,
    tag_ids: list[str] = Query(default=[]),
    year: str | None = Query(default=None, pattern=r"^\d{4}$"),
    album_type: str | None = None,
    cursor: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
) -> dict:
    items = [
        item
        for item in bootstrap(db)["albums"]
        if _contains(
            item,
            q,
            ("name", "name_en", "name_ko", "name_translated", "artist_name", "album_type", "tags"),
        )
        and (
            not group_id
            or item["group_id"] == group_id
            or any(a.get("id") == group_id for a in item.get("artists", []))
        )
        and (
            not idol_id
            or item.get("idol_id") == idol_id
            or any(a.get("id") == idol_id for a in item.get("artists", []))
        )
        and (not year or str(item["release_date"]).startswith(year))
        and (not album_type or item["album_type"] == album_type)
    ]
    return success(
        _tagged_page(
            items, tag_ids, cursor, limit, lambda item: (str(item["release_date"]), item["id"])
        ),
    )


@router.get("/events")
def list_events(
    q: str | None = Query(default=None, max_length=80),
    group_id: str | None = None,
    idol_id: str | None = None,
    tag_ids: list[str] = Query(default=[]),
    year: str | None = Query(default=None, pattern=r"^\d{4}$"),
    event_type: str | None = None,
    region: str | None = None,
    cursor: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
) -> dict:
    items = [
        item
        for item in bootstrap(db)["events"]
        if _contains(
            item,
            q,
            (
                "name",
                "name_en",
                "name_ko",
                "name_translated",
                "artist_name",
                "event_type",
                "city",
                "platform",
                "tags",
            ),
        )
        and (
            not group_id
            or item["group_id"] == group_id
            or any(a.get("id") == group_id for a in item.get("artists", []))
        )
        and (
            not idol_id
            or item.get("idol_id") == idol_id
            or any(a.get("id") == idol_id for a in item.get("artists", []))
        )
        and (not year or str(item["start_date"]).startswith(year))
        and (not event_type or item["event_type"] == event_type)
        and (not region or item["region"] == region)
    ]
    return success(
        _tagged_page(
            items, tag_ids, cursor, limit, lambda item: (str(item["start_date"]), item["id"])
        ),
    )


@router.get("/cards")
def list_cards(
    q: str | None = Query(default=None, max_length=80),
    group_id: str | None = None,
    idol_id: str | None = None,
    year: str | None = Query(default=None, pattern=r"^\d{4}$"),
    card_type: str | None = None,
    region: str | None = None,
    source: str | None = None,
    source_entity_type: str | None = Query(None, pattern="^(ALBUM|EVENT|OTHER)$"),
    source_entity_id: str | None = None,
    tag_ids: list[str] = Query(default=[]),
    sort: str = Query(default="latest", pattern="^(latest|earliest|az)$"),
    cursor: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
    db: Session = Depends(get_db),
) -> dict:
    items = [
        item
        for item in bootstrap(db)["cards"]
        if _contains(
            item,
            q,
            (
                "title",
                "card_number",
                "title_en",
                "title_ko",
                "title_translated",
                "idol_name",
                "group_name",
                "source",
                "version",
                "tags",
            ),
        )
        and (not group_id or item["group_id"] == group_id)
        and (not idol_id or item["idol_id"] == idol_id)
        and (not year or str(item["release_date"]).startswith(year))
        and (not card_type or item["card_type"] == card_type)
        and (not region or item["region"] == region)
        and (not source or source.casefold() in str(item["source"]).casefold())
        and (not source_entity_type or item.get("source_entity_type") == source_entity_type)
        and (not source_entity_id or item.get("source_entity_id") == source_entity_id)
    ]
    if sort == "az":
        return success(_tagged_page(items, tag_ids, cursor, limit, _title_key))
    return success(
        _tagged_page(items, tag_ids, cursor, limit, _release_key, reverse=sort == "latest")
    )


@router.get("/others")
@router.get("/merchandise", deprecated=True)
def list_others(
    q: str | None = Query(None, max_length=80),
    group_id: str | None = None,
    idol_id: str | None = None,
    year: str | None = None,
    tag_ids: list[str] = Query(default=[]),
    cursor: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    data = bootstrap(db)
    related = {
        card.get("source_entity_id")
        for card in data["cards"]
        if card.get("source_entity_type") == "OTHER"
        and (not group_id or card.get("group_id") == group_id)
        and (not idol_id or card.get("idol_id") == idol_id)
    }
    items = [
        item
        for item in data["others"]
        if _contains(item, q, ("name", "original_name", "description", "tags"))
        and (
            not group_id
            or item.get("group_id") == group_id
            or item["id"] in related
            or any(
                a.get("type") == "groups" and a.get("id") == group_id
                for a in item.get("artists", [])
            )
        )
        and (
            not idol_id
            or item["id"] in related
            or item.get("idol_id") == idol_id
            or any(
                a.get("type") == "idols" and a.get("id") == idol_id for a in item.get("artists", [])
            )
        )
        and (not year or item["start_date"].startswith(year))
    ]
    return success(_tagged_page(items, tag_ids, cursor, limit, _name_key))


@router.get("/search")
def search_catalog(
    q: str = Query(min_length=1, max_length=80), db: Session = Depends(get_db)
) -> dict:
    data = bootstrap(db)
    users = db.scalars(
        select(User)
        .where(
            User.display_name.ilike(f"%{q}%"),
            User.discoverable.is_(True),
            User.is_active.is_(True),
        )
        .limit(20)
    ).all()
    return success(
        {
            "groups": [
                item
                for item in data["groups"]
                if _contains(item, q, ("name", "name_en", "name_ko", "name_translated", "company"))
            ][:20],
            "idols": [
                item
                for item in data["idols"]
                if _contains(
                    item,
                    q,
                    (
                        "name",
                        "name_en",
                        "name_ko",
                        "name_translated",
                        "group_name",
                        "company",
                        "role",
                    ),
                )
            ][:20],
            "albums": [
                item
                for item in data["albums"]
                if _contains(
                    item,
                    q,
                    (
                        "name",
                        "name_en",
                        "name_ko",
                        "name_translated",
                        "artist_name",
                        "album_type",
                        "tags",
                    ),
                )
            ][:20],
            "events": [
                item
                for item in data["events"]
                if _contains(
                    item,
                    q,
                    (
                        "name",
                        "name_en",
                        "name_ko",
                        "name_translated",
                        "artist_name",
                        "event_type",
                        "city",
                        "platform",
                        "tags",
                    ),
                )
            ][:20],
            "cards": [
                item
                for item in data["cards"]
                if _contains(
                    item,
                    q,
                    (
                        "title",
                        "card_number",
                        "title_en",
                        "title_ko",
                        "title_translated",
                        "idol_name",
                        "group_name",
                        "source",
                        "original_name",
                        "tags",
                        "version",
                    ),
                )
            ][:30],
            "others": [
                item
                for item in data["others"]
                if _contains(
                    item,
                    q,
                    (
                        "name",
                        "name_en",
                        "name_ko",
                        "name_translated",
                        "artist_name",
                        "type",
                        "source",
                        "original_name",
                        "tags",
                    ),
                )
            ][:20],
            "users": [profile_payload(db, user) for user in users],
        }
    )


@router.get("/groups/{entity_id}")
def group_detail(entity_id: str, db: Session = Depends(get_db)) -> dict:
    return success(_entity(bootstrap(db), "groups", entity_id))


@router.get("/idols/{entity_id}")
def idol_detail(entity_id: str, db: Session = Depends(get_db)) -> dict:
    return success(_entity(bootstrap(db), "idols", entity_id))


@router.get("/albums/{entity_id}")
def album_detail(entity_id: str, db: Session = Depends(get_db)) -> dict:
    return success(_entity(bootstrap(db), "albums", entity_id))


@router.get("/events/{entity_id}")
def event_detail(entity_id: str, db: Session = Depends(get_db)) -> dict:
    return success(_entity(bootstrap(db), "events", entity_id))


@router.get("/cards/{entity_id}")
def card_detail(
    entity_id: str, user: User | None = Depends(optional_user), db: Session = Depends(get_db)
) -> dict:
    from app.models import (
        AlbumCard,
        Card,
        CardAlbum,
        DetectedCard,
        ScanCandidate,
        ScanSession,
        UserCollectionItem,
        UserWishlistItem,
    )

    seen = set()
    while entity_id not in seen:
        seen.add(entity_id)
        row = db.get(Card, entity_id)
        target = (row.admin_data or {}).get("merged_into") if row else None
        if not target:
            break
        entity_id = target
    if row and row.status == "OFFLINE" and user:
        owned = db.scalar(
            select(UserCollectionItem.id).where(
                UserCollectionItem.user_id == user.id, UserCollectionItem.card_id == entity_id
            )
        )
        wished = db.scalar(
            select(UserWishlistItem.id).where(
                UserWishlistItem.user_id == user.id, UserWishlistItem.card_id == entity_id
            )
        )
        binder = db.scalar(
            select(AlbumCard.id)
            .join(CardAlbum)
            .where(CardAlbum.user_id == user.id, AlbumCard.card_id == entity_id)
        )
        scan = db.scalar(
            select(DetectedCard.id)
            .join(ScanSession)
            .where(ScanSession.user_id == user.id, DetectedCard.user_confirmed_card_id == entity_id)
        ) or db.scalar(
            select(ScanCandidate.id)
            .join(DetectedCard)
            .join(ScanSession)
            .where(ScanSession.user_id == user.id, ScanCandidate.card_id == entity_id)
        )
        if owned or wished or binder or scan:
            return success(
                {**card_payload(db, row), "availability_notice": "已下架，保留历史图鉴资料"}
            )
    return success(_entity(bootstrap(db), "cards", entity_id))


@router.get("/others/{entity_id}")
@router.get("/merchandise/{entity_id}", deprecated=True)
def merchandise_detail(entity_id: str, db: Session = Depends(get_db)) -> dict:
    return success(_entity(bootstrap(db), "others", entity_id))
