"""Account-scoped library search, deliberately separate from catalog search."""

from copy import deepcopy

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.album_models import AlbumReaction
from app.common.response import DomainError
from app.common.serializers import card_payload
from app.models import Card, CardAlbum, Group, Idol, User, UserCollectionItem, UserWishlistItem
from app.modules.albums import service


def library_search(db: Session, user: User, q: str, scope: str, offset: int, limit: int) -> dict:
    needle = q.strip().casefold()
    buckets = {key: [] for key in ("owned", "wishlist", "albums")}
    if not needle:
        return {
            "groups": {k: {"items": [], "total": 0, "next_offset": None} for k in buckets},
            "total": 0,
        }
    owned = dict(
        db.execute(
            select(UserCollectionItem.card_id, UserCollectionItem.quantity).where(
                UserCollectionItem.user_id == user.id, UserCollectionItem.quantity > 0
            )
        ).all()
    )
    wished = set(
        db.scalars(
            select(UserWishlistItem.card_id).where(UserWishlistItem.user_id == user.id)
        ).all()
    )
    favorites = set(
        db.scalars(
            select(AlbumReaction.album_id).where(
                AlbumReaction.user_id == user.id, AlbumReaction.kind == "FAVORITE"
            )
        ).all()
    )
    albums = db.scalars(
        select(CardAlbum)
        .where(
            CardAlbum.status != "DELETED",
            or_(CardAlbum.user_id == user.id, CardAlbum.id.in_(favorites)),
        )
        .order_by(CardAlbum.updated_at.desc(), CardAlbum.id)
    ).all()
    documents = []
    ids = set(owned) | wished
    for album in albums:
        owner = album.user_id == user.id
        # Never inspect another author's working document, even when its title matches.
        if not owner and (
            not album.is_public
            or album.is_moderated
            or album.publication_blocked
            or album.status != "PUBLISHED"
        ):
            continue
        if not owner:
            try:
                service.get_album(db, album.id, user)
            except DomainError:
                continue
        doc = (
            deepcopy(album.published_snapshot)
            if not owner and album.published_snapshot
            else service.document(db, album)
        )
        card_ids = {s["card_id"] for s in service.occupied(doc)}
        ids.update(card_ids)
        documents.append((album, doc, card_ids, owner))
    cards = db.scalars(select(Card).where(Card.id.in_(ids)).order_by(Card.id)).all()
    idols = {
        i.id: i
        for i in db.scalars(
            select(Idol).where(Idol.id.in_({c.idol_id for c in cards if c.idol_id}))
        ).all()
    }
    groups = {
        g.id: g
        for g in db.scalars(
            select(Group).where(Group.id.in_({c.group_id for c in cards if c.group_id}))
        ).all()
    }
    matches = {}
    for card in cards:
        if not service.card_available(card):
            continue
        payload = card_payload(db, card)
        if (card.admin_data or {}).get("back_source", {}).get("copyright_status") in {
            "REVOKED",
            "UNAUTHORIZED",
            "EXPIRED",
            "FORBIDDEN",
            "OFFLINE",
            "REJECTED",
        }:
            payload["back_image_url"] = None
        terms = [
            payload.get(k, "")
            for k in (
                "card_number",
                "title",
                "title_en",
                "title_ko",
                "title_translated",
                "idol_name",
                "group_name",
                "source",
                "version",
                "card_type",
            )
        ]
        for entity in (idols.get(card.idol_id), groups.get(card.group_id)):
            if entity:
                terms.extend(
                    getattr(entity, k, "")
                    for k in ("name", "name_en", "name_ko", "name_translated")
                )
        if needle not in " ".join(str(t or "") for t in terms).casefold():
            continue
        matches[card.id] = payload
        if card.id in owned:
            buckets["owned"].append({"card": payload, "quantity": owned[card.id]})
        if card.id in wished:
            buckets["wishlist"].append({"card": payload})
    for album, doc, card_ids, owner in documents:
        title_match = needle in doc.get("name", "").casefold()
        matched_cards = card_ids & matches.keys()
        if not title_match and not matched_cards:
            continue
        buckets["albums"].append(
            {
                "album": album,
                "category": "draft"
                if owner and album.status == "DRAFT"
                else "created"
                if owner
                else "favorite",
                "match_type": "name" if title_match else "card",
            }
        )
    result = {}
    for kind, rows in buckets.items():
        # Counts span the whole account, not just the currently loaded page.
        items = rows[offset : offset + limit] if scope in ("all", kind) else []
        if kind == "albums":
            items = [
                {**row, "album": service.payload(db, row["album"], user, summary=True)}
                for row in items
            ]
        result[kind] = {
            "items": items,
            "total": len(rows),
            "next_offset": offset + limit if items and offset + limit < len(rows) else None,
        }
    return {"groups": result, "total": sum(len(rows) for rows in buckets.values())}
