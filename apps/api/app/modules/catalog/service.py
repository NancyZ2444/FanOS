from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.admin_models import ContentMetadata
from app.common.serializers import (
    card_payload,
    catalog_album_payload,
    catalog_event_payload,
)
from app.models import (
    Card,
    CatalogAlbum,
    CatalogEvent,
    Group,
    GroupMembership,
    Idol,
)
from app.modules.catalog.images import portrait_source, thumbnail_url
from app.modules.catalog.media_import import FIELDS, managed_thumbnail, public_image
from app.modules.catalog.tags import TAG_TYPES, entity_tags
from app.modules.catalog.taxonomy_models import CatalogOther


def _membership_maps(
    db: Session,
) -> tuple[dict[str, list[str]], dict[str, list[str]], dict[str, list[str]]]:
    memberships = db.scalars(select(GroupMembership)).all()
    current_by_group: dict[str, list[str]] = {}
    former_by_group: dict[str, list[str]] = {}
    groups_by_idol: dict[str, list[str]] = {}
    for membership in memberships:
        if membership.status == "void":
            continue
        target = (
            current_by_group if membership.status in {"active", "inactive"} else former_by_group
        )
        if membership.idol_id not in target.setdefault(membership.group_id, []):
            target[membership.group_id].append(membership.idol_id)
        if membership.status in {"active", "inactive"}:
            if membership.group_id not in groups_by_idol.setdefault(membership.idol_id, []):
                groups_by_idol[membership.idol_id].append(membership.group_id)
    # A rejoined member is current while earlier periods remain in the relationship table.
    for group_id, members in former_by_group.items():
        former_by_group[group_id] = [
            i for i in members if i not in current_by_group.get(group_id, [])
        ]
    return current_by_group, former_by_group, groups_by_idol


def group_payload(
    group: Group,
    current_member_ids: list[str] | None = None,
    former_member_ids: list[str] | None = None,
    image_url: str | None = None,
) -> dict[str, object]:
    return {
        "id": group.id,
        "name": group.name,
        "name_en": group.name_en,
        "name_ko": group.name_ko,
        "name_translated": group.name_translated,
        "company": group.company,
        "status": group.status,
        "member_ids": current_member_ids or [],
        "former_member_ids": former_member_ids or [],
        "debut_date": group.debut_date,
        "color_start": group.color_start,
        "color_end": group.color_end,
        "description": group.description,
        "image_url": public_image(image_url),
        "thumbnail_url": thumbnail_url("groups", group.id, public_image(image_url)),
    }


def idol_payload(
    idol: Idol,
    group_name: str = "",
    image_url: str | None = None,
    group_ids: list[str] | None = None,
) -> dict[str, object]:
    return {
        "id": idol.id,
        "name": idol.name,
        "name_en": idol.name_en,
        "name_ko": idol.name_ko,
        "name_translated": idol.name_translated,
        "group_name": group_name,
        "initials": idol.initials,
        "color_start": idol.color_start,
        "color_end": idol.color_end,
        "bio": idol.bio,
        "company": idol.company,
        "birth_date": idol.birth_date,
        "region": idol.region,
        "role": idol.role,
        "careers": idol.careers,
        "image_url": public_image(image_url),
        "thumbnail_url": thumbnail_url("idols", idol.id, public_image(image_url)),
        "group_ids": group_ids or [],
    }


def catalog_context(
    db: Session,
) -> tuple[
    dict[str, Group],
    dict[str, list[str]],
    dict[str, list[str]],
    dict[str, list[str]],
]:
    groups = db.scalars(select(Group)).all()
    current, former, by_idol = _membership_maps(db)
    return {group.id: group for group in groups}, current, former, by_idol


def bootstrap(db: Session) -> dict[str, list[dict[str, object]]]:
    hidden_groups = select(ContentMetadata.entity_id).where(
        ContentMetadata.entity_type == "groups", ContentMetadata.status != "PUBLISHED"
    )
    hidden_idols = select(ContentMetadata.entity_id).where(
        ContentMetadata.entity_type == "idols", ContentMetadata.status != "PUBLISHED"
    )
    groups = db.scalars(
        select(Group).where(Group.id.not_in(hidden_groups)).order_by(Group.name)
    ).all()
    idols = db.scalars(select(Idol).where(Idol.id.not_in(hidden_idols)).order_by(Idol.name)).all()
    cards = db.scalars(
        select(Card).where(Card.status == "PUBLISHED").order_by(Card.release_date.desc(), Card.id)
    ).all()
    albums = db.scalars(
        select(CatalogAlbum)
        .where(CatalogAlbum.is_published.is_(True))
        .order_by(CatalogAlbum.release_date.desc(), CatalogAlbum.id)
    ).all()
    events = db.scalars(
        select(CatalogEvent)
        .where(CatalogEvent.is_published.is_(True))
        .order_by(CatalogEvent.start_date.desc(), CatalogEvent.id)
    ).all()
    others = db.scalars(
        select(CatalogOther)
        .where(CatalogOther.is_published.is_(True))
        .order_by(CatalogOther.start_date.desc(), CatalogOther.id)
    ).all()
    current, former, groups_by_idol = _membership_maps(db)
    group_by_id = {group.id: group for group in groups}
    published_idol_ids = {idol.id for idol in idols}
    images = {
        (row.entity_type, row.entity_id): portrait_source(row.data or {})
        for row in db.scalars(
            select(ContentMetadata).where(
                ContentMetadata.entity_type.in_(["groups", "idols"]),
                ContentMetadata.status == "PUBLISHED",
            )
        )
    }

    result = {
        "groups": [
            group_payload(
                group,
                [i for i in current.get(group.id, []) if i in published_idol_ids],
                [i for i in former.get(group.id, []) if i in published_idol_ids],
                images.get(("groups", group.id)),
            )
            for group in groups
        ],
        "idols": [
            idol_payload(
                idol,
                (
                    group_by_id[groups_by_idol[idol.id][0]].name
                    if groups_by_idol.get(idol.id) and groups_by_idol[idol.id][0] in group_by_id
                    else ""
                ),
                images.get(("idols", idol.id)),
                [gid for gid in groups_by_idol.get(idol.id, []) if gid in group_by_id],
            )
            for idol in idols
        ],
        "cards": [card_payload(db, card) for card in cards],
        "albums": [catalog_album_payload(album) for album in albums],
        "events": [catalog_event_payload(event) for event in events],
        "others": [
            {
                "id": row.id,
                "name": row.name,
                "original_name": row.original_name,
                "start_date": row.start_date,
                "end_date": row.end_date,
                "description": row.description,
                "group_id": row.group_id,
                "image_url": (row.legacy_data or {}).get("image_url"),
                "entity_type": "OTHER",
            }
            for row in others
        ],
    }
    from app.modules.admin.catalog_extensions import CatalogRecord

    metadata = {
        (m.entity_type, m.entity_id): m.data or {}
        for m in db.scalars(
            select(ContentMetadata).where(ContentMetadata.status == "PUBLISHED")
        ).all()
    }
    operational = db.scalars(
        select(CatalogRecord).where(
            CatalogRecord.kind.in_(
                ["versions", "sources", "memberships", "company_relations", "companies"]
            )
        )
    ).all()
    companies = {r.id: r.data for r in operational if r.kind == "companies"}
    from datetime import date

    today = date.today().isoformat()
    for kind, items in result.items():
        for item in items:
            data = metadata.get((kind, item["id"]), {})
            if kind == "idols":
                item["debut_date"] = data.get("debut_date", "")
            if kind == "idols" and "career_text" in data:
                item["careers"] = (
                    [{"period": "", "title": "从艺历程", "subtitle": data["career_text"]}]
                    if data["career_text"]
                    else []
                )
            for field in (
                "artists",
                "artist_name",
                "idol_id",
                "album_id",
                "end_date",
                "business_status",
                "cover_image",
                "aliases",
                "fandom_name",
                "official_website",
                "real_name",
                "gender",
                "tags",
            ):
                if field in data:
                    item[field] = data[field]
            if kind == "others" and data.get("image_url"):
                item["image_url"] = data["image_url"]
            if kind in TAG_TYPES:
                item.update(entity_tags(db, kind, item["id"]))
            item["source_relationships"] = [
                {"id": r.data.get("id"), "type": r.data.get("type")}
                for r in operational
                if r.kind == "sources" and r.entity_id == item["id"]
            ]
            if kind in {"albums", "events", "others"}:
                item["entity_versions"] = [
                    {
                        "id": r.id,
                        **{
                            k: v
                            for k, v in r.data.items()
                            if k in {"name", "code", "cover", "release_date", "description"}
                        },
                    }
                    for r in operational
                    if r.kind == "versions" and r.entity_id == item["id"]
                ]
            if kind == "idols":
                primary = next(
                    (
                        r
                        for r in operational
                        if r.kind == "memberships"
                        and r.entity_id == item["id"]
                        and r.status != "ARCHIVED"
                        and r.data.get("is_primary")
                        and r.data.get("status") in {"active", "inactive"}
                    ),
                    None,
                )
                if primary and primary.data.get("group_id") in group_by_id:
                    item["group_name"] = group_by_id[primary.data["group_id"]].name
                item["membership_history"] = [
                    {
                        "id": m.id,
                        "group_id": m.group_id,
                        "status": m.status,
                        "start_date": m.start_date.isoformat(),
                        "end_date": m.end_date.isoformat() if m.end_date else None,
                    }
                    for m in db.scalars(
                        select(GroupMembership).where(
                            GroupMembership.idol_id == item["id"], GroupMembership.status != "void"
                        )
                    ).all()
                ]
            if kind in {"groups", "idols"}:
                relations = [
                    r
                    for r in operational
                    if r.kind == "company_relations"
                    and r.entity_id == item["id"]
                    and r.status != "ARCHIVED"
                ]
                item["company_history"] = [{"id": r.id, **r.data} for r in relations]
                current = [
                    companies[r.data["company_id"]].get("name", "")
                    for r in relations
                    if r.data.get("company_id") in companies
                    and (not r.data.get("start_date") or r.data["start_date"] <= today)
                    and (not r.data.get("end_date") or r.data["end_date"] >= today)
                ]
                if relations or any(
                    r.kind == "company_relations" and r.entity_id == item["id"] for r in operational
                ):
                    item["company"] = " / ".join(current)
            source = item.get("image_url") or item.get("cover_image")
            item["thumbnail_url"] = managed_thumbnail(data, source) or item.get("thumbnail_url")
            for field in FIELDS:
                if field in item:
                    item[field] = public_image(item[field])
            for version in item.get("entity_versions", []):
                if "cover" in version:
                    version["cover"] = public_image(version["cover"])
    return result
