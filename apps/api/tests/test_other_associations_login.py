import csv
import io

from app.core.config import get_settings

ROOT = "/api/v1/admin/console"


def test_other_requires_association_and_publishes_solo_metadata(client, admin_headers):
    def create(**values):
        return client.post(
            ROOT + "/entities/others",
            headers=admin_headers,
            json={"name": "Solo collaboration", **values},
        )

    assert create().status_code == 422
    assert create(artists=[{"type": "idols", "id": "missing"}]).status_code == 422
    image = "https://example.test/other.jpg"
    result = create(artists=[{"type": "idols", "id": "idol-aria"}], image_url=image)
    assert result.status_code == 200, result.text
    item = result.json()["data"]
    assert item["artists"] == [{"type": "idols", "id": "idol-aria"}]
    for action in ("submit", "publish"):
        response = client.post(
            ROOT + f"/entities/others/{item['id']}/actions",
            headers=admin_headers,
            json={"action": action},
        )
        assert response.status_code == 200, response.text
    public = client.get(f"/api/v1/catalog/others/{item['id']}").json()["data"]
    assert public["artists"] == item["artists"]
    assert public["artist_name"] == "Aria"
    # External originals remain admin-only until the media worker has transferred them.
    assert item["image_url"] == image
    assert public["image_url"] is None
    filtered = client.get("/api/v1/catalog/others", params={"idol_id": "idol-aria"}).json()["data"][
        "items"
    ]
    assert any(row["id"] == item["id"] for row in filtered)
    unrelated = client.get("/api/v1/catalog/others", params={"idol_id": "idol-lin"}).json()["data"][
        "items"
    ]
    assert not any(row["id"] == item["id"] for row in unrelated)


def test_other_import_supports_group_names_and_solo_names(client, admin_headers):
    from app.core.database import SessionLocal
    from app.modules.admin.import_service import entity_draft, relation_errors

    with SessionLocal() as db:
        for values in (
            {"group_name": "LUMINA"},
            {"idol_name": "Aria"},
            {"artist_names": "LUMINA|Aria"},
        ):
            draft = entity_draft(db, "others", {"name": "Other source", **values})
            assert not relation_errors(db, "others", draft)
        draft = entity_draft(db, "others", {"name": "No association"})
        assert any(e["field"] == "artists" for e in relation_errors(db, "others", draft))
    response = client.get(ROOT + "/imports/template?kind=others&format=csv", headers=admin_headers)
    fields = next(csv.reader(io.StringIO(response.content.decode("utf-8-sig"))))
    assert {"group_name", "idol_name", "artist_names", "artists"} <= set(fields)


def test_dev_code_and_first_registration_flag(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "dev_phone_code", "666666")
    body = {"method": "phone", "phone": "13855556666", "code": "666666"}
    first = client.post("/api/v1/auth/login", json=body)
    assert first.status_code == 200
    assert first.json()["data"]["is_new_user"] is True
    assert client.post("/api/v1/auth/login", json=body).json()["data"]["is_new_user"] is False
    assert client.post("/api/v1/auth/login", json={**body, "code": "123456"}).status_code == 400
    monkeypatch.setattr(get_settings(), "environment", "production")
    assert client.post("/api/v1/auth/login", json=body).status_code == 503
    assert client.post("/api/v1/auth/request-code").status_code == 503
