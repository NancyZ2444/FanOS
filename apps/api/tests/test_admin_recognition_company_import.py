"""Real artwork lookup for operations and company spreadsheet transactions."""

import io

import pytest
from conftest import scan_artwork
from PIL import Image
from sqlalchemy import select
from test_catalog_bulk import ROOT, confirm, preview

from app.core.database import SessionLocal
from app.models import Card, UserCollectionItem
from app.modules.admin.catalog_extensions import CatalogRecord


def upload_scan(client, headers, image):
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return client.post(
        ROOT + "/cards/recognize",
        headers=headers,
        files={"file": ("card.png", buffer.getvalue(), "image/png")},
    )


def test_admin_recognition_matches_draft_without_public_index_and_preserves_data(
    client, admin_headers
):
    image = scan_artwork(711)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    url = client.post(
        ROOT + "/uploads",
        headers=admin_headers,
        files={"file": ("card.png", buffer.getvalue(), "image/png")},
    ).json()["data"]["url"]
    with SessionLocal() as db:
        card = db.get(Card, "card-aria-01")
        card.image_url, card.status = url, "DRAFT"
        db.commit()
        before = [
            (c.id, c.title, c.image_url, c.status, c.admin_data) for c in db.scalars(select(Card))
        ]
        owned = [(c.id, c.quantity) for c in db.scalars(select(UserCollectionItem))]
    response = upload_scan(client, admin_headers, image)
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["status"] == "matched"
    assert data["candidates"][0]["card"]["id"] == "card-aria-01"
    assert data["candidates"][0]["card"]["status"] == "DRAFT"
    assert data["candidates"][0]["score"] >= 0.9
    assert data["image_url"]
    with SessionLocal() as db:
        assert [
            (c.id, c.title, c.image_url, c.status, c.admin_data) for c in db.scalars(select(Card))
        ] == before
        assert [(c.id, c.quantity) for c in db.scalars(select(UserCollectionItem))] == owned


def test_admin_incomplete_index_never_claims_absent_card(client, admin_headers):
    result = upload_scan(client, admin_headers, Image.new("RGB", (360, 520), "white"))
    assert result.status_code == 200
    assert result.json()["data"]["status"] == "incomplete"
    assert result.json()["data"]["unavailable_count"] > 0
    assert result.json()["data"]["candidates"] == []


def test_admin_unknown_and_ambiguous_match_require_no_catalog_writes(
    client, admin_headers, scan_index
):
    import json

    from app.core.config import get_settings
    from app.integrations.card_matcher.adapter import CardMatcherAdapter

    with SessionLocal() as db:
        cards = list(db.scalars(select(Card)))
        # Full known-image coverage with a single shared artwork deliberately creates ambiguity.
        urls = {c.id: f"http://testserver/media/{c.id}.png" for c in cards}
        for card in cards:
            card.image_url = urls[card.id]
        db.commit()
    get_settings().card_matcher_index_path.write_text(
        json.dumps(
            [
                CardMatcherAdapter.index_entry(cid, scan_index["card-aria-01"], url)
                for cid, url in urls.items()
            ]
        )
    )
    unknown = upload_scan(client, admin_headers, Image.new("RGB", (360, 520), "white")).json()[
        "data"
    ]
    assert unknown["status"] == "unrecognized"
    assert unknown["image_url"] and not unknown["candidates"]
    ambiguous = upload_scan(client, admin_headers, scan_index["card-aria-01"]).json()["data"]
    assert ambiguous["status"] == "candidates"
    assert len(ambiguous["candidates"]) > 1


def test_admin_recognition_rejects_invalid_images_and_wrong_role(
    client, admin_headers, auth_headers, admin_actor_headers
):
    bad = client.post(
        ROOT + "/cards/recognize",
        headers=admin_headers,
        files={"file": ("card.png", b"not an image", "image/png")},
    )
    assert bad.status_code == 422
    assert upload_scan(client, auth_headers, scan_artwork(1)).status_code == 401
    headers = admin_actor_headers("operation_admin", "operations-scan")
    assert upload_scan(client, headers, scan_artwork(1)).status_code == 403


@pytest.mark.parametrize("fmt", ["csv", "xlsx"])
def test_company_import_preview_confirm_repeat_and_select(client, admin_headers, fmt):
    template = client.get(
        ROOT + f"/imports/template?kind=companies&format={fmt}", headers=admin_headers
    )
    assert template.status_code == 200
    task = preview(
        client,
        admin_headers,
        "companies",
        [{"name": "New Agency", "description": "Agency notes"}],
        fmt,
    )
    assert not task["errors"]
    with SessionLocal() as db:
        assert not list(db.scalars(select(CatalogRecord).where(CatalogRecord.kind == "companies")))
    result = confirm(client, admin_headers, task)
    assert result.status_code == 200, result.text
    cid = result.json()["data"]["rows"][0]["created_id"]
    assert confirm(client, admin_headers, task).json()["data"] == result.json()["data"]
    response = client.post(
        ROOT + "/entities/groups",
        headers=admin_headers,
        json={"name": "Company import group", "company_ids": [cid]},
    )
    assert response.status_code == 200
    assert response.json()["data"]["company_ids"] == [cid]


def test_company_duplicates_edit_preview_skip_and_confirmation_race_rollback(client, admin_headers):
    client.post(
        ROOT + "/records/companies", headers=admin_headers, json={"data": {"name": "Agency One"}}
    )
    task = preview(
        client,
        admin_headers,
        "companies",
        [
            {"name": "ＡＧＥＮＣＹ   ＯＮＥ"},
            {"name": "Agency Two"},
            {"name": "agency two"},
            {"name": ""},
        ],
    )
    assert {e["row"] for e in task["errors"]} == {2, 4, 5}
    assert confirm(client, admin_headers, task).status_code == 422
    edit = client.post(
        ROOT + f"/imports/{task['id']}/edit-preview",
        headers=admin_headers,
        json={"edits": [{"row": 2, "data": {"name": "Fixed Agency"}}], "skip_rows": [4, 5]},
    )
    assert edit.status_code == 200
    corrected = edit.json()["data"]
    assert not corrected["errors"]
    client.post(
        ROOT + "/records/companies", headers=admin_headers, json={"data": {"name": "Agency Two"}}
    )
    assert confirm(client, admin_headers, corrected).status_code == 422
    with SessionLocal() as db:
        assert "Fixed Agency" not in [
            r.data["name"]
            for r in db.scalars(select(CatalogRecord).where(CatalogRecord.kind == "companies"))
        ]
