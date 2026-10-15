from datetime import UTC, datetime

from sqlalchemy import select
from test_digital_albums import BASE, create, data, page, patch

from app.album_models import AlbumFavoritePlacement, AlbumReaction
from app.core.database import SessionLocal
from app.models import CardAlbum, User

GROUPS = "/api/v1/users/me/album-favorite-groups"


def published(client, headers, name="公开卡册"):
    album = create(client, headers, name)
    album = data(patch(client, headers, album, pages=[page(["card-aria-01"])], visibility="PUBLIC"))
    return data(
        client.post(
            f"{BASE}/{album['id']}/publish", headers=headers, json={"revision": album["revision"]}
        )
    )


def collector_id():
    with SessionLocal() as db:
        return db.scalar(select(User.id).where(User.phone == "13900000000"))


def test_private_default_public_folder_and_source_revocation(client, auth_headers, admin_headers):
    album = published(client, auth_headers)
    folder = data(client.post(GROUPS, headers=admin_headers, json={"name": "舞台收藏"}))
    assert folder["is_public"] is False
    data(
        client.post(
            f"{BASE}/{album['id']}/favorite", headers=admin_headers, json={"group_id": folder["id"]}
        )
    )
    uid = collector_id()
    url = f"/api/v1/users/{uid}/favorite-albums"
    group_url = f"/api/v1/users/{uid}/album-favorite-groups"
    assert len(data(client.get(url, headers=admin_headers))["items"]) == 1
    assert data(client.get(url))["items"] == []
    assert data(client.get(url, params={"group_id": folder["id"]}))["items"] == []
    assert data(client.get(group_url))["items"] == []
    assert data(client.get(GROUPS, headers=admin_headers))["items"][0]["album_count"] == 1
    data(
        client.put(
            f"{GROUPS}/{folder['id']}",
            headers=admin_headers,
            json={"name": "舞台收藏", "is_public": True},
        )
    )
    assert data(client.get(url))["items"][0]["id"] == album["id"]
    assert data(client.get(group_url))["items"][0]["album_count"] == 1
    # Profile-wide album privacy overrides folder visibility too.
    with SessionLocal() as db:
        db.get(User, uid).albums_visible = False
        db.commit()
    assert data(client.get(url))["items"] == []
    assert data(client.get(group_url))["items"] == []
    with SessionLocal() as db:
        db.get(User, uid).albums_visible = True
        db.commit()
    data(patch(client, auth_headers, album, visibility="PRIVATE"))
    assert data(client.get(url))["items"] == []
    assert data(client.get(group_url))["items"][0]["album_count"] == 0
    item = data(client.get(url, headers=admin_headers))["items"][0]
    assert item["unavailable"] is True
    assert "cards" not in item and "cover_slots" not in item


def test_group_ownership_validation_and_legacy_ungrouped(client, auth_headers, admin_headers):
    album = published(client, auth_headers)
    folder = data(client.post(GROUPS, headers=auth_headers, json={"name": "我的分组"}))
    response = client.post(
        f"{BASE}/{album['id']}/favorite", headers=admin_headers, json={"group_id": folder["id"]}
    )
    assert response.status_code == 404
    assert (
        data(client.get("/api/v1/users/me/favorite-albums", headers=admin_headers))["items"] == []
    )
    assert (
        client.put(
            f"{GROUPS}/{folder['id']}",
            headers=admin_headers,
            json={"name": "越权", "is_public": True},
        ).status_code
        == 404
    )
    assert client.post(f"{BASE}/{album['id']}/favorite", headers=auth_headers).status_code == 422
    assert client.post(GROUPS, headers=auth_headers, json={"name": "  "}).status_code == 422
    assert client.post(GROUPS, headers=auth_headers, json={"name": "未分组"}).status_code == 422
    assert client.post(GROUPS, headers=auth_headers, json={"name": "我的分组"}).status_code == 409
    # Existing clients may omit a body; these favorites stay private and ungrouped.
    data(client.post(f"{BASE}/{album['id']}/favorite", headers=admin_headers))
    assert data(client.get(GROUPS, headers=admin_headers))["ungrouped_count"] == 1
    url = f"/api/v1/users/{collector_id()}/favorite-albums"
    assert (
        len(data(client.get(url, headers=admin_headers, params={"group_id": "ungrouped"}))["items"])
        == 1
    )
    assert data(client.get(url))["items"] == []
    assert client.post(GROUPS, json={"name": "登录才可创建"}).status_code == 401


def test_saved_time_order_move_pagination_and_unfavorite(client, auth_headers, admin_headers):
    albums = [published(client, auth_headers, name) for name in ["A", "B"]]
    folder = data(
        client.post(GROUPS, headers=admin_headers, json={"name": "最近收藏", "is_public": True})
    )
    for i, album in enumerate(albums):
        data(client.post(f"{BASE}/{album['id']}/favorite", headers=admin_headers))
        with SessionLocal() as db:
            reaction = db.scalar(select(AlbumReaction).where(AlbumReaction.album_id == album["id"]))
            reaction.created_at = datetime(2026, 10, i + 1, tzinfo=UTC)
            db.commit()
    uid = collector_id()
    url = f"/api/v1/users/{uid}/favorite-albums"
    before = data(client.get(url, headers=admin_headers))["items"]
    assert [a["id"] for a in before] == [a["id"] for a in reversed(albums)]
    move_url = f"/api/v1/users/me/favorite-albums/{albums[0]['id']}/group"
    data(client.put(move_url, headers=admin_headers, json={"group_id": folder["id"]}))
    # Idempotent collection does not change timestamp or existing folder.
    data(client.post(f"{BASE}/{albums[0]['id']}/favorite", headers=admin_headers))
    after = data(client.get(url, headers=admin_headers))["items"]
    assert [a["favorited_at"] for a in after] == [a["favorited_at"] for a in before]
    assert after[1]["favorite_group_id"] == folder["id"]
    first = data(client.get(url, headers=admin_headers, params={"limit": 1}))
    assert first["next_offset"] == 1 and first["items"][0]["id"] == albums[1]["id"]
    assert (
        data(client.get(url, headers=admin_headers, params={"group_id": folder["id"]}))["items"][0][
            "id"
        ]
        == albums[0]["id"]
    )
    # Group moves never change source ownership or public status.
    with SessionLocal() as db:
        assert db.get(CardAlbum, albums[0]["id"]).user_id != uid
    data(client.delete(f"{BASE}/{albums[0]['id']}/favorite", headers=admin_headers))
    with SessionLocal() as db:
        assert db.scalar(select(AlbumFavoritePlacement)) is None
    assert data(client.get(url))["items"] == []
    assert (
        client.put(move_url, headers=admin_headers, json={"group_id": folder["id"]}).status_code
        == 404
    )


def test_migration_preserves_legacy_favorites_and_defaults_to_private(tmp_path):
    import importlib.util
    from pathlib import Path

    import sqlalchemy as sa
    from alembic.migration import MigrationContext
    from alembic.operations import Operations

    path = Path(__file__).parents[1] / "migrations/versions/f614_album_favorite_groups.py"
    spec = importlib.util.spec_from_file_location("favorite_groups_migration", path)
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    engine = sa.create_engine(f"sqlite:///{tmp_path / 'migration.db'}")
    with engine.begin() as connection:
        connection.exec_driver_sql("CREATE TABLE users (id VARCHAR(64) PRIMARY KEY)")
        connection.exec_driver_sql(
            "CREATE TABLE digital_album_reactions (id VARCHAR(64) PRIMARY KEY)"
        )
        connection.exec_driver_sql("INSERT INTO users VALUES ('user-1')")
        connection.exec_driver_sql("INSERT INTO digital_album_reactions VALUES ('favorite-1')")
        with Operations.context(MigrationContext.configure(connection)):
            migration.upgrade()
        connection.exec_driver_sql(
            "INSERT INTO digital_album_favorite_groups (id,user_id,name) "
            "VALUES ('group-1','user-1','收藏')"
        )
        assert (
            connection.exec_driver_sql(
                "SELECT is_public FROM digital_album_favorite_groups"
            ).scalar()
            == 0
        )
        assert (
            connection.exec_driver_sql(
                "SELECT count(*) FROM digital_album_favorite_placements"
            ).scalar()
            == 0
        )
        assert (
            connection.exec_driver_sql("SELECT id FROM digital_album_reactions").scalar()
            == "favorite-1"
        )
        with Operations.context(MigrationContext.configure(connection)):
            migration.downgrade()
        assert not sa.inspect(connection).has_table("digital_album_favorite_groups")
        assert (
            connection.exec_driver_sql("SELECT id FROM digital_album_reactions").scalar()
            == "favorite-1"
        )
    engine.dispose()
