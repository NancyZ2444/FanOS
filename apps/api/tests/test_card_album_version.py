"""Cards store a selected version belonging to their album, with an authoritative name."""

from test_admin_console import ROOT, payload

from app.core.database import SessionLocal
from app.modules.admin.catalog_extensions import CatalogRecord


def test_card_album_version_ownership_and_name(client, admin_headers):
    with SessionLocal() as db:
        db.add_all(
            [
                CatalogRecord(
                    id="card-version-a",
                    kind="versions",
                    entity_type="albums",
                    entity_id="album-starlit",
                    data={"name": "Limited", "code": "LTD"},
                ),
                CatalogRecord(
                    id="card-version-other",
                    kind="versions",
                    entity_type="albums",
                    entity_id="album-bloom",
                    data={"name": "Other"},
                ),
                CatalogRecord(
                    id="card-version-wrong-type",
                    kind="versions",
                    entity_type="events",
                    entity_id="album-starlit",
                    data={"name": "Invalid owner"},
                ),
                CatalogRecord(
                    id="card-version-archived",
                    kind="versions",
                    entity_type="albums",
                    entity_id="album-starlit",
                    status="ARCHIVED",
                    data={"name": "Archived"},
                ),
            ]
        )
        db.commit()
    for invalid in ["card-version-other", "card-version-wrong-type", "card-version-archived"]:
        response = client.post(
            ROOT + "/cards", headers=admin_headers, json=payload(entity_version_id=invalid)
        )
        assert response.status_code == 422
        assert any(e["field"] == "entity_version_id" for e in response.json()["data"]["details"])
    response = client.post(
        ROOT + "/cards",
        headers=admin_headers,
        json=payload(entity_version_id="card-version-a", version="Incorrect text"),
    )
    assert response.status_code == 200, response.text
    card = response.json()["data"]
    assert card["entity_version_id"] == "card-version-a"
    assert card["version"] == "Limited"
    response = client.put(
        ROOT + "/cards/" + card["id"],
        headers=admin_headers,
        json=payload(entity_version_id=None, version=""),
    )
    assert response.status_code == 200
    assert response.json()["data"]["entity_version_id"] is None
    assert response.json()["data"]["version"] == ""
