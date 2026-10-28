"""Real relationship counts and nickname search; only fixture data is changed."""

from app.core.database import SessionLocal
from app.models import User, UserFollow


def data(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]


def test_search_uses_real_nickname_case_insensitive_and_respects_visibility(client, auth_headers):
    with SessionLocal() as db:
        db.get(User, "current-user").display_name = "西瓜桑"
        db.get(User, "admin-demo").display_name = "Fan OS 运营"
        db.get(User, "admin-demo").discoverable = True
        db.get(User, "user-luna").display_name = "Fan 不可发现"
        db.get(User, "user-luna").discoverable = False
        db.get(User, "user-mint").display_name = "Fan 停用"
        db.get(User, "user-mint").is_active = False
        db.commit()
    matches = data(client.get("/api/v1/users/search", headers=auth_headers, params={"q": " Fan "}))
    assert [(row["id"], row["display_name"]) for row in matches["items"]] == [
        ("admin-demo", "Fan OS 运营")
    ]
    assert data(client.get("/api/v1/users/search", headers=auth_headers, params={"q": "fan"})) == matches
    assert data(client.get("/api/v1/users/search", headers=auth_headers, params={"q": "%"}))["items"] == []
    assert data(client.get("/api/v1/users/search", headers=auth_headers, params={"q": " "}))["items"] == []


def test_follow_counts_match_lists_and_idempotent_mutations(client, auth_headers):
    before = data(client.get("/api/v1/me/profile", headers=auth_headers))
    followed = data(client.put("/api/v1/users/admin-demo/follow", headers=auth_headers))
    repeated = data(client.put("/api/v1/users/admin-demo/follow", headers=auth_headers))
    assert followed == repeated
    mine = data(client.get("/api/v1/me/profile", headers=auth_headers))
    following = data(client.get("/api/v1/users/current-user/following", headers=auth_headers))["items"]
    followers = data(client.get("/api/v1/users/current-user/followers", headers=auth_headers))["items"]
    target = data(client.get("/api/v1/users/admin-demo", headers=auth_headers))
    assert followed["my_following_count"] == mine["following_count"] == len(following)
    assert followed["my_followers_count"] == mine["followers_count"] == len(followers)
    assert followed["followers_count"] == target["followers_count"]
    assert mine["following_count"] == before["following_count"] + 1
    removed = data(client.delete("/api/v1/users/admin-demo/follow", headers=auth_headers))
    again = data(client.delete("/api/v1/users/admin-demo/follow", headers=auth_headers))
    assert removed == again
    assert removed["my_following_count"] == before["following_count"]


def test_inactive_accounts_do_not_inflate_visible_relationship_counts(client, auth_headers):
    with SessionLocal() as db:
        db.get(User, "user-luna").is_active = False
        db.add(UserFollow(follower_id="current-user", following_id="user-mint"))
        db.commit()
    profile = data(client.get("/api/v1/me/profile", headers=auth_headers))
    for kind, count in [("following", "following_count"), ("followers", "followers_count")]:
        rows = data(client.get(f"/api/v1/users/current-user/{kind}", headers=auth_headers))["items"]
        assert profile[count] == len(rows)
        assert all(row["id"] != "user-luna" for row in rows)
    with SessionLocal() as db:
        db.get(User, "user-mint").followers_list_visible = False
        db.commit()
    response = client.get("/api/v1/users/user-mint/followers", headers=auth_headers)
    assert response.status_code == 403
    assert response.json()["error_code"] == "RELATION_LIST_PRIVATE"
