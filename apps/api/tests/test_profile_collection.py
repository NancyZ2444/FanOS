def test_profile_privacy_follow_and_self_follow_guard(client, auth_headers):
    mine = client.get("/api/v1/me/profile", headers=auth_headers).json()["data"]
    assert mine["display_name"] == "星河收藏家"
    assert mine["owned"] == {"card-aria-01": 1}

    patched = client.patch(
        "/api/v1/me/profile",
        headers=auth_headers,
        json={"bio": "新的收藏简介", "privacy": {"likes_visible": False}},
    )
    assert patched.json()["data"]["bio"] == "新的收藏简介"

    public = client.get("/api/v1/users/user-mint", headers=auth_headers).json()["data"]
    assert public["liked_card_ids"] is None
    assert public["relation_status"] == "follows_you"

    followed = client.put("/api/v1/users/user-mint/follow", headers=auth_headers)
    assert followed.json()["data"]["relation_status"] == "mutual"
    repeated = client.put("/api/v1/users/user-mint/follow", headers=auth_headers)
    assert repeated.json()["data"]["relation_status"] == "mutual"
    self_follow = client.put("/api/v1/users/current-user/follow", headers=auth_headers)
    assert self_follow.status_code == 400
    assert self_follow.json()["error_code"] == "CANNOT_FOLLOW_SELF"


def test_collection_wishlist_and_album_operations(client, auth_headers):
    incremented = client.post("/api/v1/me/collection/card-aria-01/increment", headers=auth_headers)
    assert incremented.json()["data"]["quantity"] == 2
    added = client.put(
        "/api/v1/me/collection/card-lin-01",
        headers=auth_headers,
        json={"quantity": 1},
    )
    assert added.status_code == 200
    removed_like = client.delete("/api/v1/me/wishlist/card-lin-01", headers=auth_headers)
    assert removed_like.json()["data"]["wished"] is False

    legacy = client.post("/api/v1/me/card-albums", headers=auth_headers, json={"name": "旧入口"})
    assert legacy.status_code == 409
    album = client.post(
        "/api/v1/albums",
        headers=auth_headers,
        json={"name": "测试卡册", "work_mode": "BOOK"},
    ).json()["data"]
    updated = client.put(
        f"/api/v1/me/card-albums/{album['id']}/cards",
        headers=auth_headers,
        json={"card_ids": ["card-aria-01", "card-lin-01"], "revision": album["revision"]},
    )
    assert updated.json()["data"]["card_count"] == 2
