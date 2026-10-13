def test_health_login_and_catalog_contract(client):
    health = client.get("/health")
    assert health.status_code == 200
    assert health.json()["data"]["status"] == "ok"

    login = client.post(
        "/api/v1/auth/login",
        json={"method": "phone", "phone": "13800000000", "code": "123456"},
    )
    assert login.status_code == 200
    assert login.json()["data"]["user"]["id"] == "current-user"

    catalog = client.get("/api/v1/catalog/bootstrap").json()["data"]
    assert len(catalog["groups"]) == 3
    assert len(catalog["idols"]) == 6
    assert len(catalog["cards"]) == 7
    assert len(catalog["albums"]) == 4
    assert len(catalog["events"]) == 5
    assert len(catalog["others"]) == 3
    assert catalog["cards"][0]["idol_name"]
    assert catalog["groups"][0]["debut_date"]
    assert "region" not in catalog["groups"][0]
    assert catalog["groups"][0]["name_en"]
    assert catalog["groups"][0]["name_ko"]
    assert catalog["idols"][0]["careers"]
    assert catalog["albums"][0]["name_translated"]
    assert "front_image_url" in catalog["albums"][0]
    assert "back_image_url" in catalog["albums"][0]


def test_catalog_discovery_filters_search_and_details(client):
    albums = client.get(
        "/api/v1/catalog/albums", params={"group_id": "group-lumina", "year": "2026"}
    ).json()["data"]
    assert albums["total"] == 2
    assert {item["name"] for item in albums["items"]} == {"Starlit", "Blue Hour"}

    cards = client.get(
        "/api/v1/catalog/cards",
        params={"idol_id": "idol-aria", "region": "China", "sort": "latest"},
    ).json()["data"]
    assert cards["total"] == 1
    assert cards["items"][0]["id"] == "card-aria-02"

    searched = client.get("/api/v1/catalog/search", params={"q": "Starlit"}).json()["data"]
    assert searched["albums"][0]["id"] == "album-starlit"
    assert {item["id"] for item in searched["cards"]} >= {
        "card-aria-01",
        "card-lin-01",
    }
    korean_search = client.get("/api/v1/catalog/search", params={"q": "스타릿"}).json()["data"]
    assert korean_search["albums"][0]["id"] == "album-starlit"

    detail = client.get("/api/v1/catalog/events/event-afterglow-tour")
    assert detail.status_code == 200
    assert detail.json()["data"]["event_type"] == "Tour"
    missing = client.get("/api/v1/catalog/merchandise/missing")
    assert missing.status_code == 404


def test_daily_draw_is_idempotent_and_limited_to_three(client, auth_headers):
    first = client.post(
        "/api/v1/daily-cards/draw",
        headers=auth_headers,
        json={"draw_request_id": "request-1"},
    )
    assert first.status_code == 200
    repeated = client.post(
        "/api/v1/daily-cards/draw",
        headers=auth_headers,
        json={"draw_request_id": "request-1"},
    )
    assert repeated.json()["data"]["draw_id"] == first.json()["data"]["draw_id"]
    for index in (2, 3):
        assert (
            client.post(
                "/api/v1/daily-cards/draw",
                headers=auth_headers,
                json={"draw_request_id": f"request-{index}"},
            ).status_code
            == 200
        )
    limited = client.post(
        "/api/v1/daily-cards/draw",
        headers=auth_headers,
        json={"draw_request_id": "request-4"},
    )
    assert limited.status_code == 409
    assert limited.json()["error_code"] == "DAILY_CARD_LIMIT_REACHED"
