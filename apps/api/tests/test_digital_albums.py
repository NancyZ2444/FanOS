from copy import deepcopy

from app.core.database import SessionLocal
from app.models import Card, CardAlbum, UserCollectionItem, new_id

BASE = "/api/v1/albums"


def test_stacked_cover_summary_tracks_main_order_and_published_snapshot(client, auth_headers):
    album = create(client, auth_headers)
    pages = [page(["card-aria-01", "card-lin-01"] * 3)]
    ids = [s["id"] for s in pages[0]["slots"]]
    view = {
        "card_order": ids[::-1],
        "order_customized": True,
        "featured_slot_id": ids[2],
        "default_mode": "CARDS",
        "cover_style": "STACK_V1",
        "display_fields": ["idol", "source"],
        "background": {"type": "SOLID", "colors": ["#EDE8FF"]},
    }
    album = data(
        patch(
            client,
            auth_headers,
            album,
            pages=pages,
            card_view=view,
            confirm_duplicates=True,
            visibility="PUBLIC",
        )
    )
    expected = [ids[2], ids[5], ids[4], ids[3], ids[1]]
    shelf = next(
        a for a in data(client.get(BASE, headers=auth_headers))["items"] if a["id"] == album["id"]
    )
    assert "pages" not in shelf and "card_order" not in shelf["card_view"]
    assert [s["id"] for s in shelf["cover_slots"]] == expected
    assert shelf["card_view"]["default_mode"] == "CARDS"
    assert shelf["card_view"]["display_fields"] == ["idol", "source"]
    assert set(shelf["cards"]) == {"card-aria-01", "card-lin-01"}
    album = data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    view["featured_slot_id"] = ids[0]
    album = data(patch(client, auth_headers, album, card_view=view))
    assert data(client.get(f"{BASE}/{album['id']}"))["cover_slots"][0]["id"] == ids[2]
    assert album["cover_slots"][0]["id"] == ids[0]
    # Revoked imagery must not reappear on the newly added shelf cover path.
    with SessionLocal() as db:
        db.get(Card, "card-aria-01").status = "OFFLINE"
        db.commit()
    shelf = next(
        a for a in data(client.get(BASE, headers=auth_headers))["items"] if a["id"] == album["id"]
    )
    assert shelf["cards"]["card-aria-01"]["available"] is False
    assert "image_url" not in shelf["cards"]["card-aria-01"]


def data(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def create(client, headers, name="我的小卡册"):
    return data(client.post(BASE, headers=headers, json={"name": name}))


def page(card_ids, grid=None):
    size = grid or len(card_ids)
    return {
        "id": new_id("page"),
        "grid_count": size,
        "slots": [
            {"id": new_id("slot"), "card_id": card_ids[i] if i < len(card_ids) else None}
            for i in range(size)
        ],
    }


def patch(client, headers, album, **changes):
    return client.patch(
        f"{BASE}/{album['id']}", headers=headers, json={"revision": album["revision"], **changes}
    )


def test_private_draft_publish_and_revision_conflict(client, auth_headers, admin_headers):
    album = create(client, auth_headers)
    assert album["visibility"] == "PRIVATE" and album["status"] == "DRAFT"
    assert client.get(f"{BASE}/{album['id']}").status_code == 403
    assert client.get(f"{BASE}/{album['id']}", headers=admin_headers).status_code == 403
    newer = data(patch(client, auth_headers, album, name="新名称", visibility="PUBLIC"))
    assert patch(client, auth_headers, album, name="过期覆盖").status_code == 409
    assert client.get(f"{BASE}/{album['id']}").status_code == 403  # public draft is not published
    published = data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": newer["revision"]},
        )
    )
    assert data(client.get(f"{BASE}/{album['id']}"))["name"] == "新名称"
    editing = data(patch(client, auth_headers, published, name="未完成版本"))
    assert data(client.get(f"{BASE}/{album['id']}"))["name"] == "新名称"
    data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": editing["revision"]},
        )
    )
    assert data(client.get(f"{BASE}/{album['id']}"))["name"] == "未完成版本"


def test_instances_independent_of_collection_and_carousel_order(client, auth_headers):
    data(
        client.put("/api/v1/me/collection/card-aria-01", headers=auth_headers, json={"quantity": 0})
    )
    album = create(client, auth_headers)
    pages = [page(["card-aria-01", "card-aria-01", "card-lin-01"])]
    assert (
        patch(client, auth_headers, album, pages=pages).json()["error_code"]
        == "ALBUM_DUPLICATE_CONFIRM_REQUIRED"
    )
    album = data(patch(client, auth_headers, album, pages=pages, confirm_duplicates=True))
    assert album["card_count"] == 3
    with SessionLocal() as db:
        assert (
            db.query(UserCollectionItem)
            .filter_by(user_id="current-user", card_id="card-aria-01")
            .count()
            == 0
        )
    order = [s["id"] for s in reversed(pages[0]["slots"])]
    view = {
        **album["card_view"],
        "card_order": order,
        "featured_slot_id": order[1],
        "order_customized": True,
    }
    album = data(patch(client, auth_headers, album, card_view=view))
    assert [s["id"] for s in album["pages"][0]["slots"]] != order
    assert album["card_view"]["card_order"] == order
    pages[0]["slots"][1]["card_id"] = None
    album = data(patch(client, auth_headers, album, pages=pages))
    assert album["card_view"]["featured_slot_id"] is None
    assert len(album["card_view"]["card_order"]) == 2
    data(client.delete(f"{BASE}/{album['id']}?revision={album['revision']}", headers=auth_headers))
    assert client.get(f"{BASE}/{album['id']}", headers=auth_headers).status_code == 404


def test_layout_confirmation_page_operations_and_display_are_independent(client, auth_headers):
    album = create(client, auth_headers)
    album = data(
        patch(client, auth_headers, album, pages=[page(["card-aria-01", "card-lin-01"], 3)])
    )
    first = album["pages"][0]
    assert (
        client.patch(
            f"{BASE}/{album['id']}/pages/{first['id']}",
            headers=auth_headers,
            json={"revision": album["revision"], "grid_count": 1},
        ).status_code
        == 409
    )
    album = data(
        client.patch(
            f"{BASE}/{album['id']}/pages/{first['id']}",
            headers=auth_headers,
            json={"revision": album["revision"], "grid_count": 1, "confirm_removal": True},
        )
    )
    album = data(
        client.post(
            f"{BASE}/{album['id']}/pages/{first['id']}/duplicate",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    assert album["page_count"] == 2 and album["card_count"] == 2
    assert album["pages"][1]["slots"][0]["id"] != first["slots"][0]["id"]
    pages_before = deepcopy(album["pages"])
    album = data(
        client.put(
            f"{BASE}/{album['id']}/display",
            headers=auth_headers,
            json={
                "revision": album["revision"],
                "display_type": "DOUBLE",
                "visual_style": "REALISTIC",
            },
        )
    )
    assert album["pages"] == pages_before
    album = data(
        client.put(
            f"{BASE}/{album['id']}/pages/reorder",
            headers=auth_headers,
            json={
                "revision": album["revision"],
                "page_ids": [p["id"] for p in reversed(album["pages"])],
            },
        )
    )
    assert album["pages"][1]["id"] == first["id"]


def test_quota_normal_pro_expiry_and_legacy_endpoint(client, auth_headers, admin_headers):
    initial = data(client.get(f"{BASE}/quota", headers=auth_headers))["album_count"]
    for index in range(10 - initial):
        create(client, auth_headers, f"Normal {index}")
    assert client.post(BASE, headers=auth_headers, json={"name": "第11本"}).status_code == 409
    assert (
        client.post(
            "/api/v1/me/card-albums", headers=auth_headers, json={"name": "旧接口绕过"}
        ).status_code
        == 409
    )
    data(
        client.put(
            "/api/v1/admin/console/album-entitlements/current-user",
            headers=admin_headers,
            json={"plan": "PRO"},
        )
    )
    for index in range(20):
        create(client, auth_headers, f"Pro {index}")
    assert client.post(BASE, headers=auth_headers, json={"name": "第31本"}).status_code == 409
    album = data(client.get(BASE, headers=auth_headers))["items"][0]
    album = data(client.get(f"{BASE}/{album['id']}", headers=auth_headers))
    album = data(patch(client, auth_headers, album, pages=[page([], 1) for _ in range(20)]))
    assert (
        client.post(
            f"{BASE}/{album['id']}/pages",
            headers=auth_headers,
            json={"revision": album["revision"], "grid_count": 1},
        ).status_code
        == 409
    )
    data(
        client.put(
            "/api/v1/admin/console/album-entitlements/current-user",
            headers=admin_headers,
            json={"plan": "PRO", "expires_at": "2020-01-01T00:00:00Z"},
        )
    )
    assert data(client.get(f"{BASE}/quota", headers=auth_headers))["plan"] == "NORMAL"
    assert data(client.get(f"{BASE}/{album['id']}", headers=auth_headers))["page_count"] == 20
    album = data(patch(client, auth_headers, album, description="会员到期，依然可编辑"))
    assert (
        client.post(
            f"{BASE}/{album['id']}/pages",
            headers=auth_headers,
            json={"revision": album["revision"], "grid_count": 1},
        ).status_code
        == 409
    )


def test_copyright_redaction_on_all_views_and_snapshot(client, auth_headers):
    album = create(client, auth_headers)
    cover = {"elements": [{"id": "cover-card", "type": "CARD", "content": "card-aria-01"}]}
    album = data(
        patch(
            client,
            auth_headers,
            album,
            pages=[page(["card-aria-01"])],
            cover=cover,
            visibility="PUBLIC",
        )
    )
    album = data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    with SessionLocal() as db:
        card = db.get(Card, "card-aria-01")
        card.image_url = "http://copyright-test.invalid/secret.jpg"
        card.admin_data = {"front_source": {"copyright_status": "REVOKED"}}
        db.commit()
    for path in [
        f"{BASE}/{album['id']}",
        f"{BASE}/{album['id']}/preview",
        "/api/v1/users/current-user/albums",
    ]:
        response = client.get(path)
        assert response.status_code == 200
        assert "secret.jpg" not in response.text
    assert data(client.get(f"{BASE}/{album['id']}"))["cards"]["card-aria-01"]["available"] is False


def test_social_favorites_are_references_and_permission_enforced(
    client, auth_headers, admin_headers
):
    album = create(client, auth_headers)
    album = data(patch(client, auth_headers, album, visibility="PUBLIC"))
    album = data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    assert client.post(f"{BASE}/{album['id']}/like", headers=auth_headers).status_code == 422
    for _ in range(2):
        data(client.post(f"{BASE}/{album['id']}/like", headers=admin_headers))
        data(client.post(f"{BASE}/{album['id']}/favorite", headers=admin_headers))
    assert data(client.get(f"{BASE}/{album['id']}", headers=admin_headers))["like_count"] == 1
    assert patch(client, admin_headers, album, name="他人修改").status_code == 403
    assert (
        data(client.get("/api/v1/users/me/favorite-albums", headers=admin_headers))["items"][0][
            "id"
        ]
        == album["id"]
    )
    album = data(patch(client, auth_headers, album, visibility="PRIVATE"))
    assert client.get(f"{BASE}/{album['id']}", headers=admin_headers).status_code == 403
    unavailable = data(client.get("/api/v1/users/me/favorite-albums", headers=admin_headers))[
        "items"
    ][0]
    assert unavailable["unavailable"]
    data(client.delete(f"{BASE}/{album['id']}/favorite", headers=admin_headers))


def test_id_collisions_foreign_cards_and_moderation(client, auth_headers, admin_headers):
    album = create(client, auth_headers)
    pages = [page(["card-aria-01"])]
    album = data(patch(client, auth_headers, album, pages=pages))
    other = create(client, auth_headers)
    assert patch(client, auth_headers, other, pages=pages).status_code == 422
    assert (
        patch(client, auth_headers, album, pages=[page(["not-an-official-card"])]).status_code
        == 422
    )
    duplicate = data(
        client.post(
            f"{BASE}/{album['id']}/duplicate",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    assert duplicate["id"] != album["id"] and duplicate["card_count"] == 1
    assert duplicate["pages"][0]["slots"][0]["id"] != pages[0]["slots"][0]["id"]
    album = data(patch(client, auth_headers, album, visibility="PUBLIC"))
    album = data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    data(
        client.put(
            f"/api/v1/admin/console/digital-albums/{album['id']}/moderation",
            headers=admin_headers,
            json={"offline": True, "reason": "测试人工复核"},
        )
    )
    assert client.get(f"{BASE}/{album['id']}").status_code == 403
    assert client.get(f"{BASE}/{album['id']}", headers=auth_headers).status_code == 200
    assert (
        client.put(
            "/api/v1/admin/console/album-settings", headers=auth_headers, json={}
        ).status_code
        == 403
    )


def test_normal_page_limit_blank_cover_and_global_theme(client, auth_headers):
    album = create(client, auth_headers)
    album = data(patch(client, auth_headers, album, pages=[page([], 1) for _ in range(10)]))
    assert album["card_count"] == 0 and album["page_count"] == 10
    assert (
        client.post(
            f"{BASE}/{album['id']}/pages",
            headers=auth_headers,
            json={"revision": album["revision"], "grid_count": 1},
        ).status_code
        == 409
    )
    data(
        client.put(
            f"{BASE}/preferences",
            headers=auth_headers,
            json={"shelf_theme": "natural-wood", "view_mode": "LIST"},
        )
    )
    assert (
        data(client.get(BASE, headers=auth_headers))["preferences"]["shelf_theme"] == "natural-wood"
    )
    assert (
        client.put(
            f"{BASE}/preferences",
            headers=auth_headers,
            json={"shelf_theme": "non-existent", "view_mode": "SHELF"},
        ).status_code
        == 422
    )
    data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    with SessionLocal() as db:
        assert db.get(CardAlbum, album["id"]).published_snapshot is not None


def test_publication_cannot_bypass_moderation_via_private_publish(
    client, auth_headers, admin_headers
):
    data(
        client.put(
            "/api/v1/admin/console/album-settings",
            headers=admin_headers,
            json={"blocked_terms": ["blocked-word"]},
        )
    )
    album = create(client, auth_headers, "blocked-word")
    album = data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    assert patch(client, auth_headers, album, visibility="PUBLIC").status_code == 422
    assert client.get(f"{BASE}/{album['id']}").status_code == 403
    assert (
        data(client.get(f"{BASE}/{album['id']}", headers=auth_headers))["revision"]
        == album["revision"]
    )


def test_assets_and_system_resource_validation_and_roles(client, auth_headers, admin_headers):
    assets = data(
        client.post(
            f"{BASE}/card-assets",
            headers=auth_headers,
            json={"card_ids": ["card-aria-01", "not-real"]},
        )
    )["cards"]
    assert assets["card-aria-01"]["available"] and not assets["not-real"]["available"]
    assert client.post(f"{BASE}/card-assets", json={"card_ids": []}).status_code == 401
    path = "/api/v1/admin/console/album-resources/test-star"
    resource = {"id": "test-star", "name": "测试贴纸", "kind": "STICKER", "config": {"symbol": "✦"}}
    assert client.put(path, headers=auth_headers, json=resource).status_code == 403
    data(client.put(path, headers=admin_headers, json=resource))
    assert (
        client.put(
            path,
            headers=admin_headers,
            json={**resource, "config": {"url": "https://untrusted.example/image.png"}},
        ).status_code
        == 422
    )
    assert (
        client.put(
            path,
            headers=admin_headers,
            json={**resource, "kind": "BACKGROUND", "config": {"colors": ["bad-color"]}},
        ).status_code
        == 422
    )
    book = create(client, auth_headers)
    book = data(patch(client, auth_headers, book, visibility="PUBLIC"))
    book = data(
        client.post(
            f"{BASE}/{book['id']}/publish",
            headers=auth_headers,
            json={"revision": book["revision"]},
        )
    )
    data(
        client.post(
            f"{BASE}/{book['id']}/report", headers=admin_headers, json={"reason": "需要运营复核"}
        )
    )
    assert (
        data(client.get("/api/v1/admin/console/digital-albums", headers=admin_headers))["items"][0][
            "report_count"
        ]
        == 1
    )


def test_search_pagination_and_favorites_do_not_expose_unpublished_name(
    client, auth_headers, admin_headers
):
    book = create(client, auth_headers, "Published Star")
    book = data(patch(client, auth_headers, book, visibility="PUBLIC"))
    book = data(
        client.post(
            f"{BASE}/{book['id']}/publish",
            headers=auth_headers,
            json={"revision": book["revision"]},
        )
    )
    data(client.post(f"{BASE}/{book['id']}/favorite", headers=admin_headers))
    data(patch(client, auth_headers, book, name="Private Work In Progress"))
    path = "/api/v1/users/me/favorite-albums"
    assert (
        len(data(client.get(path + "?q=Published&sort=name", headers=admin_headers))["items"]) == 1
    )
    assert data(client.get(path + "?q=Private", headers=admin_headers))["items"] == []
    public = "/api/v1/users/current-user/albums"
    assert data(client.get(public + "?q=Private"))["items"] == []
    assert len(data(client.get(public + "?q=Published"))["items"]) == 1
    result = data(client.get(BASE + "?limit=1", headers=auth_headers))
    assert len(result["items"]) == 1 and result["next_offset"] == 1


def test_catalog_merge_preserves_digital_slot_instances_and_published_snapshot(
    client, auth_headers, admin_headers
):
    book = create(client, auth_headers)
    placements = page(["card-aria-01", "card-aria-01", "card-lin-01"])
    book = data(
        patch(
            client,
            auth_headers,
            book,
            pages=[placements],
            confirm_duplicates=True,
            visibility="PUBLIC",
        )
    )
    book = data(
        client.post(
            f"{BASE}/{book['id']}/publish",
            headers=auth_headers,
            json={"revision": book["revision"]},
        )
    )
    root = "/api/v1/admin/console/cards/merge"
    plan = data(
        client.post(
            root,
            headers=admin_headers,
            json={"source_id": "card-aria-01", "target_id": "card-lin-01"},
        )
    )
    assert any(r["label"] == "数字卡册" for r in plan["relations"])
    data(
        client.post(
            root,
            headers=admin_headers,
            json={
                "source_id": "card-aria-01",
                "target_id": "card-lin-01",
                "preview": False,
                "expected": plan["expected"],
            },
        )
    )
    merged = data(client.get(f"{BASE}/{book['id']}", headers=auth_headers))
    assert merged["revision"] == book["revision"] + 1
    assert [s["id"] for s in merged["pages"][0]["slots"]] == [s["id"] for s in placements["slots"]]
    public = data(client.get(f"{BASE}/{book['id']}"))
    assert len(public["pages"][0]["slots"]) == 3
    assert all(s["card_id"] == "card-lin-01" for s in public["pages"][0]["slots"])
