from copy import deepcopy

from app.core.database import SessionLocal
from app.models import Card, CardAlbum, User, UserCollectionItem, new_id

BASE = "/api/v1"


def data(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def search(client, headers, q, **query):
    return data(client.get(f"{BASE}/me/library/search", headers=headers, params={"q": q, **query}))


def album(client, headers, name, cards=(), public=False, publish=False):
    a = data(client.post(f"{BASE}/albums", headers=headers, json={"name": name}))
    a = data(
        client.patch(
            f"{BASE}/albums/{a['id']}",
            headers=headers,
            json={
                "revision": a["revision"],
                "visibility": "PUBLIC" if public else "PRIVATE",
                "confirm_duplicates": True,
                "pages": [
                    {
                        "id": new_id("page"),
                        "grid_count": 9,
                        "slots": [
                            {"id": new_id("slot"), "card_id": cards[i] if i < len(cards) else None}
                            for i in range(9)
                        ],
                    }
                ],
            },
        )
    )
    if publish:
        a = data(
            client.post(
                f"{BASE}/albums/{a['id']}/publish",
                headers=headers,
                json={"revision": a["revision"]},
            )
        )
    return a


def test_account_scope_independent_relations_and_literal_query(client, auth_headers):
    before = data(client.get(f"{BASE}/me/collection", headers=auth_headers))
    assert client.get(f"{BASE}/me/library/search?q=Aria").status_code == 401
    found = search(client, auth_headers, " aRiA ")["groups"]
    assert found["owned"]["total"] == 1
    assert found["owned"]["items"][0]["quantity"] == 1
    assert found["wishlist"]["total"] == 0
    assert search(client, auth_headers, "Yuna")["groups"]["owned"]["total"] == 0
    assert search(client, auth_headers, "%")["total"] == 0
    assert search(client, auth_headers, "   ")["total"] == 0
    assert data(client.get(f"{BASE}/me/collection", headers=auth_headers)) == before
    data(client.put(f"{BASE}/me/wishlist/card-aria-01", headers=auth_headers))
    result = search(client, auth_headers, "Aria")
    assert result["groups"]["owned"]["total"] == result["groups"]["wishlist"]["total"] == 1
    only = search(client, auth_headers, "Aria", scope="wishlist")
    assert not only["groups"]["owned"]["items"]
    assert only["groups"]["wishlist"]["items"]
    assert (
        client.get(f"{BASE}/me/library/search?scope=catalog", headers=auth_headers).status_code
        == 422
    )


def test_album_inner_cards_beyond_cover_and_draft_filter(client, auth_headers):
    draft = album(client, auth_headers, "Outer title", ["card-aria-01"] * 5 + ["card-lin-01"])
    published = album(client, auth_headers, "Finished book", publish=True)
    result = search(client, auth_headers, "Lin")["groups"]["albums"]["items"]
    match = next(i for i in result if i["album"]["id"] == draft["id"])
    assert match["category"] == "draft" and match["match_type"] == "card"
    drafts = data(client.get(f"{BASE}/albums?status=DRAFT", headers=auth_headers))["items"]
    complete = data(client.get(f"{BASE}/albums?status=PUBLISHED", headers=auth_headers))["items"]
    assert draft["id"] in {a["id"] for a in drafts}
    assert draft["id"] not in {a["id"] for a in complete}
    assert published["id"] in {a["id"] for a in complete}
    assert published["id"] not in {a["id"] for a in drafts}
    assert client.get(f"{BASE}/albums?status=DELETED", headers=auth_headers).status_code == 422


def test_favorite_search_only_published_snapshot(client, auth_headers, admin_headers):
    a = album(client, admin_headers, "Public moon", ["card-aria-01"], public=True, publish=True)
    data(client.post(f"{BASE}/albums/{a['id']}/favorite", headers=auth_headers))
    hidden = album(
        client, admin_headers, "Unrelated moon", ["card-lin-01"], public=True, publish=True
    )
    with SessionLocal() as db:
        row = db.get(CardAlbum, a["id"])
        row.name = "UNPUBLISHED SECRET"
        # Store a different unpublished page; the published Aria snapshot remains intact.
        from app.album_models import AlbumPage, AlbumSlot

        page = db.query(AlbumPage).filter_by(album_id=a["id"]).first()
        slot = db.query(AlbumSlot).filter_by(page_id=page.id, card_id="card-aria-01").first()
        slot.card_id = "card-lin-01"
        db.commit()
    found = search(client, auth_headers, "Aria")["groups"]["albums"]["items"]
    result = next(i for i in found if i["album"]["id"] == a["id"])
    assert result["category"] == "favorite" and result["album"]["name"] == "Public moon"
    assert not search(client, auth_headers, "UNPUBLISHED SECRET")["groups"]["albums"]["items"]
    assert hidden["id"] not in {
        i["album"]["id"] for i in search(client, auth_headers, "moon")["groups"]["albums"]["items"]
    }
    assert a["id"] not in {
        i["album"]["id"] for i in search(client, auth_headers, "Lin")["groups"]["albums"]["items"]
    }
    with SessionLocal() as db:
        db.get(CardAlbum, a["id"]).is_public = False
        db.commit()
    assert not search(client, auth_headers, "Public moon")["groups"]["albums"]["items"]


def test_unavailable_author_and_revoked_cards_are_excluded(client, auth_headers, admin_headers):
    a = album(client, admin_headers, "Inactive owner", ["card-aria-01"], public=True, publish=True)
    data(client.post(f"{BASE}/albums/{a['id']}/favorite", headers=auth_headers))
    with SessionLocal() as db:
        db.get(User, a["user_id"]).is_active = False
        c = db.get(Card, "card-aria-01")
        c.admin_data = {
            **(c.admin_data or {}),
            "back_image_url": "https://example.test/revoked.jpg",
            "back_source": {"copyright_status": "REVOKED"},
        }
        db.commit()
    assert not search(client, auth_headers, "Inactive owner")["groups"]["albums"]["items"]
    assert (
        search(client, auth_headers, "Aria")["groups"]["owned"]["items"][0]["card"][
            "back_image_url"
        ]
        is None
    )
    with SessionLocal() as db:
        db.get(Card, "card-aria-01").status = "OFFLINE"
        db.commit()
    assert search(client, auth_headers, "Aria")["groups"]["owned"]["total"] == 0


def test_pagination_full_totals_version_and_translation(client, auth_headers):
    with SessionLocal() as db:
        template = db.get(Card, "card-aria-01")
        values = {
            c.name: deepcopy(getattr(template, c.name))
            for c in Card.__table__.columns
            if c.name not in {"id", "card_number", "created_at", "updated_at"}
        }
        values.update(version="Unique edition", title_translated="星河典藏")
        for i in range(25):
            identifier = f"search-card-{i:02}"
            db.add(Card(id=identifier, **values))
            db.add(UserCollectionItem(user_id="current-user", card_id=identifier, quantity=3))
        db.commit()
    first = search(client, auth_headers, "Unique edition", scope="owned")["groups"]["owned"]
    second = search(client, auth_headers, "Unique edition", scope="owned", offset=20)["groups"][
        "owned"
    ]
    assert first["total"] == 25 and len(first["items"]) == 20 and first["next_offset"] == 20
    assert len(second["items"]) == 5 and second["next_offset"] is None
    assert not (
        {i["card"]["id"] for i in first["items"]} & {i["card"]["id"] for i in second["items"]}
    )
    assert search(client, auth_headers, "星河典藏")["groups"]["owned"]["total"] == 25
