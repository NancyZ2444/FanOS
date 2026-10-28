from copy import deepcopy

from sqlalchemy import select
from test_digital_albums import BASE, data, patch

from app.album_models import AlbumPage, AlbumWork
from app.core.database import SessionLocal
from app.models import CardAlbum
from app.modules.albums.migration_v11 import convert, migrate_works


def create(client, headers, mode="CARDS", **extra):
    return data(
        client.post(BASE, headers=headers, json={"name": "V1.1", "work_mode": mode, **extra})
    )


def test_create_type_required_atomic_retry_and_cross_type_writes(client, auth_headers):
    assert client.post(BASE, headers=auth_headers, json={"name": "old"}).status_code == 422
    a = create(client, auth_headers, request_id="same-request")
    assert a["pages"] == [] and a["card_instances"] == [] and a["cover"] == {}
    assert create(client, auth_headers, request_id="same-request")["id"] == a["id"]
    assert (
        client.post(
            BASE,
            headers=auth_headers,
            json={"name": "different", "work_mode": "BOOK", "request_id": "same-request"},
        ).status_code
        == 409
    )
    for fields in (
        {"work_mode": "BOOK"},
        {"card_view": {"default_mode": "BOOK"}},
        {"cover": {}},
        {"pages": []},
        {"display_type": "DOUBLE"},
    ):
        assert patch(client, auth_headers, a, **fields).status_code in {409, 422}
    b = create(client, auth_headers, "BOOK")
    assert patch(client, auth_headers, b, card_instances=[]).status_code == 422


def test_independent_instances_duplicate_order_featured_and_snapshot(client, auth_headers):
    a = create(client, auth_headers)
    slots = [{"id": "one", "card_id": "card-aria-01"}, {"id": "two", "card_id": "card-aria-01"}]
    assert patch(client, auth_headers, a, card_instances=slots).status_code == 409
    a = data(patch(client, auth_headers, a, card_instances=slots, confirm_duplicates=True))
    view = {
        **a["card_view"],
        "card_order": ["two", "one"],
        "order_customized": True,
        "featured_slot_id": "two",
    }
    a = data(patch(client, auth_headers, a, card_view=view, visibility="PUBLIC"))
    assert a["page_count"] == 0 and a["card_count"] == 2
    with SessionLocal() as db:
        assert not db.scalars(select(AlbumPage).where(AlbumPage.album_id == a["id"])).all()
    a = data(
        client.post(
            f"{BASE}/{a['id']}/publish", headers=auth_headers, json={"revision": a["revision"]}
        )
    )
    a = data(patch(client, auth_headers, a, card_instances=slots[:1], confirm_removal=True))
    assert a["card_view"]["featured_slot_id"] == "one"
    published = data(client.get(f"{BASE}/{a['id']}"))
    assert published["card_count"] == 2 and published["card_view"]["featured_slot_id"] == "two"
    copy = data(
        client.post(
            f"{BASE}/{a['id']}/duplicate", headers=auth_headers, json={"revision": a["revision"]}
        )
    )
    assert copy["work_mode"] == "CARDS" and copy["visibility"] == "PRIVATE"
    assert copy["card_instances"][0]["id"] != "one"


def test_capacity_retains_legacy_excess_and_rejects_growth(client, auth_headers):
    a = create(client, auth_headers)
    slots = [{"id": f"instance-{i}", "card_id": "card-aria-01"} for i in range(16)]
    assert (
        patch(client, auth_headers, a, card_instances=slots, confirm_duplicates=True).status_code
        == 409
    )
    with SessionLocal() as db:
        db.get(AlbumWork, a["id"]).instances = slots
        db.commit()
    a = data(client.get(f"{BASE}/{a['id']}", headers=auth_headers))
    a = data(patch(client, auth_headers, a, name="超额仍可编辑"))
    assert a["card_count"] == 16
    assert (
        client.post(
            f"{BASE}/{a['id']}/duplicate", headers=auth_headers, json={"revision": a["revision"]}
        ).status_code
        == 409
    )
    a = data(patch(client, auth_headers, a, card_instances=slots[:15], confirm_removal=True))
    assert a["card_count"] == 15


def test_four_scenes_and_immutable_admin_entries(client, auth_headers, admin_headers):
    base = "/api/v1/admin/console/album-materials"
    value = {
        "id": "card-bg",
        "name": "卡片底色",
        "kind": "BACKGROUND",
        "scene": "CARD_BACKGROUND",
        "config": {"colors": ["#FFFFFF"]},
    }
    data(client.post(f"{base}/CARD_BACKGROUND", headers=admin_headers, json=value))
    assert client.post(f"{base}/ALBUM_PAGE", headers=admin_headers, json=value).status_code == 422
    assert (
        client.put(
            f"{base}/ALBUM_PAGE/card-bg",
            headers=admin_headers,
            json={**value, "scene": "ALBUM_PAGE"},
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/api/v1/admin/console/album-resources/card-bg",
            headers=admin_headers,
            json={**value, "scene": "ALBUM_PAGE"},
        ).status_code
        == 409
    )
    a = create(client, auth_headers, "BOOK")
    assert (
        patch(client, auth_headers, a, cover={"background": {"resource_id": "card-bg"}}).status_code
        == 422
    )
    c = create(client, auth_headers)
    c = data(
        patch(
            client,
            auth_headers,
            c,
            card_view={"default_mode": "CARDS", "background": {"resource_id": "card-bg"}},
        )
    )
    assert c["card_view"]["background"]["resource_snapshot"]["id"] == "card-bg"
    assert (
        client.post(
            f"{base}/ALBUM_PAGE",
            headers=admin_headers,
            json={
                **value,
                "id": "page-sticker",
                "kind": "STICKER",
                "scene": "ALBUM_PAGE",
                "config": {"symbol": "★"},
            },
        ).status_code
        == 422
    )


def test_type_and_scene_filters_apply_before_pagination(client, auth_headers):
    create(client, auth_headers, "BOOK")
    cards = create(client, auth_headers, "CARDS")
    page = data(client.get(BASE, headers=auth_headers, params={"work_mode": "CARDS", "limit": 1}))
    assert [a["id"] for a in page["items"]] == [cards["id"]]
    for scene in ("SHELF", "ALBUM_COVER", "ALBUM_PAGE", "CARD_BACKGROUND"):
        result = data(client.get(BASE + "/resources", params={"scene": scene}))
        assert result["items"] and all(r["scene"] == scene for r in result["items"])


def test_migration_is_lossless_and_requires_explicit_resolution(client, auth_headers):
    doc = {
        "cover": {"elements": [{"type": "TEXT", "content": "keep"}]},
        "pages": [
            {"id": "p", "slots": [{"id": "a", "card_id": "same"}, {"id": "b", "card_id": "same"}]}
        ],
        "card_view": {"card_order": ["b", "a"], "order_customized": True},
    }
    before = deepcopy(doc)
    converted = convert(doc, "CARDS")
    assert [s["id"] for s in converted["card_instances"]] == ["b", "a"]
    assert doc == before and converted["pages"] == []
    with SessionLocal() as db:
        original = db.get(CardAlbum, "album-starlit")
        timestamp = original.updated_at
        report = migrate_works(db)
        assert next(r for r in report if r["id"] == original.id)["mode"] == "REVIEW"
        archive = deepcopy(db.get(AlbumWork, original.id).migration_archive)
        migrate_works(db, {original.id: "CARDS"})
        db.commit()
        assert db.get(AlbumWork, original.id).migration_archive == archive
        assert db.get(CardAlbum, original.id).updated_at == timestamp
