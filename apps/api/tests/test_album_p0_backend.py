from io import BytesIO

from PIL import Image
from test_digital_albums import BASE, create, data, patch

from app.album_models import AlbumEntitlement, AlbumPreferences
from app.core.database import SessionLocal
from app.models import CardAlbum

ADMIN = "/api/v1/admin/console"


def resource(client, headers, resource_id="custom", **changes):
    value = {
        "id": resource_id,
        "name": "历史贴纸",
        "kind": "STICKER",
        "scene": "ALBUM_COVER",
        "config": {"symbol": "♥"},
        **changes,
    }
    data(client.post(f"{ADMIN}/album-resources", headers=headers, json=value))
    return value


def sticker(element_id="original", resource_id="custom"):
    return {"id": element_id, "type": "STICKER", "content": resource_id}


def test_material_history_is_per_instance_and_survives_catalog_edit(
    client, auth_headers, admin_headers
):
    value = resource(client, admin_headers)
    album = create(client, auth_headers)
    album = data(patch(client, auth_headers, album, cover={"elements": [sticker()]}))
    assert album["cover"]["elements"][0]["resource_snapshot"]["config"]["symbol"] == "♥"
    data(
        client.put(
            f"{ADMIN}/album-resources/custom",
            headers=admin_headers,
            json={**value, "config": {"symbol": "☀"}, "status": "OFFLINE"},
        )
    )
    album = data(client.get(f"{BASE}/{album['id']}", headers=auth_headers))
    original = album["cover"]["elements"][0]
    original["x"] = 0.4
    original["resource_snapshot"]["config"]["symbol"] = "forged"
    album = data(patch(client, auth_headers, album, cover={"elements": [original]}))
    assert album["cover"]["elements"][0]["resource_snapshot"]["config"]["symbol"] == "♥"
    assert (
        patch(
            client, auth_headers, album, cover={"elements": [original, sticker("extra")]}
        ).status_code
        == 422
    )
    assert (
        client.post(
            f"{BASE}/{album['id']}/duplicate",
            headers=auth_headers,
            json={"revision": album["revision"]},
        ).status_code
        == 409
    )
    album = data(patch(client, auth_headers, album, cover={"elements": []}))
    assert patch(client, auth_headers, album, cover={"elements": [sticker()]}).status_code == 422


def test_pro_expiry_preserves_instances_but_blocks_new_and_copy(
    client, auth_headers, admin_headers
):
    resource(client, admin_headers, membership="PRO", locked_preview=True)
    album = create(client, auth_headers)
    assert patch(client, auth_headers, album, cover={"elements": [sticker()]}).status_code == 422
    items = data(client.get(f"{BASE}/resources", headers=auth_headers))["items"]
    assert next(i for i in items if i["id"] == "custom")["available"] is False
    with SessionLocal() as db:
        db.add(AlbumEntitlement(user_id=album["user_id"], plan="PRO"))
        db.commit()
    album = data(patch(client, auth_headers, album, cover={"elements": [sticker()]}))
    with SessionLocal() as db:
        db.get(AlbumEntitlement, album["user_id"]).plan = "NORMAL"
        db.commit()
    album = data(patch(client, auth_headers, album, name="会员到期仍可编辑"))
    assert album["cover"]["elements"][0]["resource_snapshot"]["config"]["symbol"] == "♥"
    assert (
        client.post(
            f"{BASE}/{album['id']}/duplicate",
            headers=auth_headers,
            json={"revision": album["revision"]},
        ).status_code
        == 409
    )


def test_material_create_does_not_overwrite_and_delete_constraints(client, admin_headers):
    value = resource(client, admin_headers, status="DRAFT")
    assert (
        client.post(
            f"{ADMIN}/album-resources", headers=admin_headers, json={**value, "name": "Overwrite"}
        ).status_code
        == 409
    )
    assert (
        client.delete(f"{ADMIN}/album-resources/custom", headers=admin_headers).status_code == 200
    )
    resource(client, admin_headers, status="PUBLISHED")
    assert (
        client.put(
            f"{ADMIN}/album-resources/custom",
            headers=admin_headers,
            json={**value, "status": "DRAFT"},
        ).status_code
        == 409
    )
    assert (
        client.delete(f"{ADMIN}/album-resources/custom", headers=admin_headers).status_code == 409
    )


def test_image_upload_keeps_transparency_and_canonical_background(
    client, auth_headers, admin_headers
):
    image = Image.new("RGBA", (16, 16), (255, 0, 0, 128))
    buffer = BytesIO()
    image.save(buffer, "PNG")
    upload = data(
        client.post(
            f"{ADMIN}/album-resources/upload",
            headers=admin_headers,
            data={"kind": "STICKER"},
            files={"file": ("alpha.png", buffer.getvalue(), "image/png")},
        )
    )
    from app.integrations.storage import get_storage

    with Image.open(BytesIO(get_storage().read_bytes(upload["url"]))) as stored:
        assert stored.mode == "RGBA" and stored.getpixel((1, 1))[3] == 128
    resource(
        client,
        admin_headers,
        resource_id="photo",
        kind="BACKGROUND",
        scene="ALBUM_COVER",
        config={"type": "IMAGE", "image_url": upload["url"]},
    )
    album = create(client, auth_headers)
    album = data(
        patch(
            client,
            auth_headers,
            album,
            cover={
                "background": {
                    "type": "IMAGE",
                    "resource_id": "photo",
                    "image_url": "https://forged.invalid/image",
                }
            },
        )
    )
    assert album["cover"]["background"]["image_url"] == upload["url"]
    assert (
        patch(
            client,
            auth_headers,
            create(client, auth_headers, mode="CARDS"),
            card_view={"default_mode": "CARDS", "background": {"resource_id": "photo"}},
        ).status_code
        == 422
    )
    assert (
        patch(
            client,
            auth_headers,
            album,
            cover={"background": {"type": "IMAGE", "image_url": upload["url"]}},
        ).status_code
        == 422
    )


def test_shelf_offline_and_legacy_snapshot_backfill(client, auth_headers, admin_headers):
    album = create(client, auth_headers)
    # Legacy custom stickers predate snapshots; material edit must backfill first.
    value = resource(client, admin_headers)
    with SessionLocal() as db:
        row = db.get(CardAlbum, album["id"])
        row.cover_config = {"elements": [sticker()]}
        preferences = db.get(AlbumPreferences, album["user_id"])
        if preferences:
            preferences.shelf_snapshot = None
        else:
            db.add(
                AlbumPreferences(
                    user_id=album["user_id"], shelf_theme="cream-white", view_mode="SHELF"
                )
            )
        db.commit()
    data(
        client.put(
            f"{ADMIN}/album-resources/custom",
            headers=admin_headers,
            json={**value, "config": {"symbol": "☀"}},
        )
    )
    album = data(client.get(f"{BASE}/{album['id']}", headers=auth_headers))
    assert album["cover"]["elements"][0]["resource_snapshot"]["config"]["symbol"] == "♥"
    shelf = {
        "id": "cream-white",
        "name": "奶油白",
        "kind": "SHELF",
        "scene": "SHELF",
        "status": "OFFLINE",
        "config": {"colors": ["#000000", "#111111"], "ledge": "#222222"},
    }
    data(client.put(f"{ADMIN}/album-resources/cream-white", headers=admin_headers, json=shelf))
    saved = data(
        client.put(
            f"{BASE}/preferences",
            headers=auth_headers,
            json={"shelf_theme": "cream-white", "view_mode": "LIST"},
        )
    )
    assert saved["shelf_snapshot"]["config"]["colors"][0] == "#F4EEE7"


def test_moderation_review_snapshot_reports_and_deleted_restore(
    client, auth_headers, admin_headers, second_app_headers
):
    album = create(client, auth_headers, "已发布标题")
    album = data(patch(client, auth_headers, album, visibility="PUBLIC"))
    album = data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    data(
        client.post(
            f"{BASE}/{album['id']}/report", headers=second_app_headers, json={"reason": "需要复核"}
        )
    )
    album = data(patch(client, auth_headers, album, name="尚未发布的编辑"))
    detail = data(client.get(f"{ADMIN}/digital-albums/{album['id']}", headers=admin_headers))
    assert detail["name"] == "已发布标题" and detail["preview_version"] == "PUBLISHED"
    report_id = detail["reports"][0]["id"]
    data(
        client.put(
            f"{ADMIN}/digital-albums/{album['id']}/moderation",
            headers=admin_headers,
            json={
                "status": "OFFLINE",
                "reason_code": "IMAGE",
                "reason": "图片不当",
                "resolve_report_ids": [report_id],
            },
        )
    )
    assert client.get(f"{BASE}/{album['id']}").status_code == 403
    assert (
        client.post(
            f"{BASE}/{album['id']}/duplicate",
            headers=auth_headers,
            json={"revision": album["revision"]},
        ).status_code
        == 403
    )
    # The App sends the complete form, including unchanged PUBLIC visibility.
    album = data(
        patch(
            client,
            auth_headers,
            album,
            visibility="PUBLIC",
            name="尚未发布的编辑",
            cover=album["cover"],
            card_view=album["card_view"],
            pages=album["pages"],
        )
    )
    review = data(
        client.post(
            f"{BASE}/{album['id']}/review-request",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )["review_request"]
    album = data(patch(client, auth_headers, album, name="申请后修改"))
    preview = data(
        client.get(f"{ADMIN}/digital-albums/{album['id']}?preview=review", headers=admin_headers)
    )
    assert preview["name"] == "尚未发布的编辑" and preview["reports"][0]["status"] == "resolved"
    assert (
        client.put(
            f"{ADMIN}/digital-albums/{album['id']}/moderation",
            headers=admin_headers,
            json={"status": "NORMAL", "reason": "恢复"},
        ).status_code
        == 409
    )
    data(
        client.put(
            f"{ADMIN}/digital-albums/{album['id']}/moderation",
            headers=admin_headers,
            json={"status": "NORMAL", "reason": "恢复", "review_id": review["id"]},
        )
    )
    assert client.get(f"{BASE}/{album['id']}").status_code == 403
    visible = data(client.get(f"/api/v1/users/{album['user_id']}/albums"))["items"]
    assert album["id"] not in {item["id"] for item in visible}
    album = data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    assert album["review_status"] == "NONE"
    assert data(client.get(f"{BASE}/{album['id']}"))["name"] == "申请后修改"
    logs = data(client.get(f"{ADMIN}/digital-albums/{album['id']}", headers=admin_headers))["logs"]
    assert {"offline", "restore", "request_review"} <= {log["action"] for log in logs}
    data(client.delete(f"{BASE}/{album['id']}?revision={album['revision']}", headers=auth_headers))
    assert (
        client.put(
            f"{ADMIN}/digital-albums/{album['id']}/moderation",
            headers=admin_headers,
            json={"status": "NORMAL", "reason": "不能复活"},
        ).status_code
        == 409
    )


def test_limits_require_bound_impact_confirmation_and_preserve_omitted(client, admin_headers):
    values = data(client.get(f"{ADMIN}/album-settings", headers=admin_headers))["limits"]
    assert values["normal_color_daily"] == 3 and values["pro_color_monthly"] == 300
    reduced = {**values, "normal_albums": 1}
    assert (
        client.put(f"{ADMIN}/album-settings", headers=admin_headers, json=reduced).status_code
        == 409
    )
    impact = data(
        client.post(f"{ADMIN}/album-settings/impact", headers=admin_headers, json=reduced)
    )
    assert impact["requires_confirmation"]
    data(
        client.put(
            f"{ADMIN}/album-settings?confirm_impact={impact['confirmation_token']}",
            headers=admin_headers,
            json=reduced,
        )
    )
    saved = data(
        client.put(
            f"{ADMIN}/album-settings", headers=admin_headers, json={"blocked_terms": ["bad"]}
        )
    )
    assert saved["normal_albums"] == 1 and saved["normal_color_daily"] == 3


def test_direct_restore_requires_publish_and_private_publish_cannot_bypass(
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
    data(
        client.put(
            f"{ADMIN}/digital-albums/{album['id']}/moderation",
            headers=admin_headers,
            json={"status": "RESTRICTED", "reason": "待核查"},
        )
    )
    album = data(patch(client, auth_headers, album, visibility="PRIVATE"))
    assert (
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": album["revision"]},
        ).status_code
        == 403
    )
    data(
        client.put(
            f"{ADMIN}/digital-albums/{album['id']}/moderation",
            headers=admin_headers,
            json={"status": "NORMAL", "reason": "解除限制"},
        )
    )
    album = data(client.get(f"{BASE}/{album['id']}", headers=auth_headers))
    assert album["visibility"] == "PRIVATE" and album["review_status"] == "RESTORED"
    album = data(patch(client, auth_headers, album, visibility="PUBLIC"))
    assert client.get(f"{BASE}/{album['id']}").status_code == 403
    album = data(
        client.post(
            f"{BASE}/{album['id']}/publish",
            headers=auth_headers,
            json={"revision": album["revision"]},
        )
    )
    assert client.get(f"{BASE}/{album['id']}").status_code == 200
    assert album["review_status"] == "NONE"


def test_page_copy_cannot_reuse_offline_materials(client, auth_headers, admin_headers):
    from test_digital_albums import page

    value = resource(
        client, admin_headers, kind="BACKGROUND", scene="ALBUM_PAGE", config={"colors": ["#ABCDEF"]}
    )
    album = create(client, auth_headers)
    inner = page([], 1)
    inner["config"] = {"background": {"resource_id": "custom"}}
    album = data(patch(client, auth_headers, album, pages=[inner]))
    data(
        client.put(
            f"{ADMIN}/album-resources/custom",
            headers=admin_headers,
            json={**value, "status": "OFFLINE"},
        )
    )
    assert (
        client.post(
            f"{BASE}/{album['id']}/pages/{inner['id']}/duplicate",
            headers=auth_headers,
            json={"revision": album["revision"]},
        ).status_code
        == 409
    )
    retained = data(client.get(f"{BASE}/{album['id']}", headers=auth_headers))
    assert retained["pages"][0]["config"]["background"]["resource_snapshot"]["config"][
        "colors"
    ] == ["#ABCDEF"]
