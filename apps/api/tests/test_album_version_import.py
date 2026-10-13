"""Album editions share a work and resolve spreadsheet artist names to stable IDs."""

import csv
import io
import json

import pytest
from openpyxl import load_workbook
from sqlalchemy import select
from test_admin_console import payload
from test_catalog_bulk import ROOT, confirm, preview

from app.admin_models import AdminImportTask, ContentMetadata
from app.core.database import SessionLocal
from app.models import Card, CatalogAlbum, Group
from app.modules.admin.catalog_extensions import CatalogRecord


def versions(client, headers, album_id):
    response = client.get(ROOT + "/records/versions?entity_id=" + album_id, headers=headers)
    assert response.status_code == 200, response.text
    items = response.json()["data"]["items"]
    assert all(item["entity_type"] == "albums" and item["entity_id"] == album_id for item in items)
    return {item["data"]["name"]: item for item in items}


def create_album(client, headers, **extra):
    response = client.post(
        ROOT + "/entities/albums",
        headers=headers,
        json={"name": "Edition work", "artists": [{"type": "idols", "id": "idol-aria"}], **extra},
    )
    assert response.status_code == 200, response.text
    return response.json()["data"]


def create_version(client, headers, album_id, name):
    response = client.post(
        ROOT + "/records/versions",
        headers=headers,
        json={"entity_type": "albums", "entity_id": album_id, "data": {"name": name}},
    )
    assert response.status_code == 200, response.text
    return response.json()["data"]


def album_artists(db, album_id):
    meta = db.scalar(
        select(ContentMetadata).where(
            ContentMetadata.entity_type == "albums", ContentMetadata.entity_id == album_id
        )
    )
    return {(artist["type"], artist["id"]) for artist in meta.data["artists"]}


@pytest.mark.parametrize("fmt", ["csv", "xlsx"])
def test_album_template_exposes_versions_and_multiple_artist_names(client, admin_headers, fmt):
    response = client.get(
        ROOT + f"/imports/template?kind=albums&format={fmt}", headers=admin_headers
    )
    assert response.status_code == 200
    if fmt == "csv":
        fields = next(csv.reader(io.StringIO(response.content.decode("utf-8-sig"))))
    else:
        workbook = load_workbook(io.BytesIO(response.content))
        fields = list(next(workbook.active.values))
        workbook.close()
    assert {"name", "versions", "artist_names"} <= set(fields)


@pytest.mark.parametrize("fmt", ["csv", "xlsx"])
def test_album_version_rows_share_parent_with_artist_order_independent_identity(
    client, admin_headers, fmt
):
    task = preview(
        client,
        admin_headers,
        "albums",
        [
            {"name": "Shared work", "artist_names": "Aria|Lin", "versions": "Moon|Dawn"},
            {"name": "Shared work", "artist_names": "Lin|Aria", "versions": "Night"},
        ],
        fmt,
    )
    assert task["errors"] == []
    assert len(task["rows"]) == 2
    with SessionLocal() as db:
        assert db.scalar(select(CatalogAlbum).where(CatalogAlbum.name == "Shared work")) is None
    response = confirm(client, admin_headers, task)
    assert response.status_code == 200, response.text
    result = response.json()["data"]
    ids = {row["created_id"] for row in result["rows"]}
    assert len(ids) == 1
    album_id = ids.pop()
    edition_records = versions(client, admin_headers, album_id)
    assert set(edition_records) == {"Moon", "Dawn", "Night"}
    with SessionLocal() as db:
        album = db.get(CatalogAlbum, album_id)
        assert album.name == "Shared work"
        assert set(album.versions) == {"Moon", "Dawn", "Night"}
        assert album_artists(db, album_id) == {("idols", "idol-aria"), ("idols", "idol-lin")}
    repeated = confirm(client, admin_headers, task)
    assert repeated.status_code == 200
    assert repeated.json()["data"] == result
    assert {name: row["id"] for name, row in versions(client, admin_headers, album_id).items()} == {
        name: row["id"] for name, row in edition_records.items()
    }


@pytest.mark.parametrize(
    ("columns", "expected"),
    [
        (
            {"artist_names": "LUMINA|Aria|Lin", "versions": "A|B"},
            {("groups", "group-lumina"), ("idols", "idol-aria"), ("idols", "idol-lin")},
        ),
        (
            {"idol_names": "Aria|Lin", "version": "A"},
            {("idols", "idol-aria"), ("idols", "idol-lin")},
        ),
        (
            {"idol_name": "Aria|Lin", "version": "A"},
            {("idols", "idol-aria"), ("idols", "idol-lin")},
        ),
        (
            {"group_name": "LUMINA", "idol_name": "Aria", "versions": "A"},
            {("groups", "group-lumina"), ("idols", "idol-aria")},
        ),
        (
            {
                "artists": json.dumps(
                    [{"type": "groups", "id": "group-aster"}, {"type": "idols", "id": "idol-aria"}]
                ),
                "versions": "A",
            },
            {("groups", "group-aster"), ("idols", "idol-aria")},
        ),
    ],
)
def test_album_import_resolves_names_and_legacy_aliases_to_artist_ids(
    client, admin_headers, columns, expected
):
    task = preview(client, admin_headers, "albums", [{"name": "Named collaborators", **columns}])
    assert task["errors"] == []
    data = task["rows"][0]["data"]
    assert {(artist["type"], artist["id"]) for artist in data["artists"]} == expected
    assert data["versions"] == (columns.get("versions") or columns["version"]).split("|")
    response = confirm(client, admin_headers, task)
    assert response.status_code == 200, response.text
    album_id = response.json()["data"]["rows"][0]["created_id"]
    with SessionLocal() as db:
        assert album_artists(db, album_id) == expected
        assert db.get(CatalogAlbum, album_id).name == "Named collaborators"


@pytest.mark.parametrize("ambiguous", [False, True])
def test_album_import_rejects_unknown_or_ambiguous_artist_name_per_row(
    client, admin_headers, ambiguous
):
    if ambiguous:
        with SessionLocal() as db:
            # The untyped artist_names column must not guess between an idol and a group.
            db.add(Group(id="group-also-aria", name="Aria"))
            db.commit()
    task = preview(
        client,
        admin_headers,
        "albums",
        [
            {
                "name": "Unsafe attribution",
                "artist_names": "Aria" if ambiguous else "Missing idol",
                "versions": "A",
            }
        ],
    )
    assert task["rows"] == []
    assert {(error["row"], error["field"]) for error in task["errors"]} == {(2, "artist_names")}
    assert confirm(client, admin_headers, task).status_code == 422
    with SessionLocal() as db:
        assert (
            db.scalar(select(CatalogAlbum).where(CatalogAlbum.name == "Unsafe attribution")) is None
        )


@pytest.mark.parametrize("same_row", [False, True])
def test_album_import_duplicate_version_is_reported_with_row_and_versions_field(
    client, admin_headers, same_row
):
    row = {
        "name": "Duplicate edition",
        "artist_names": "Aria|Lin",
        "versions": "A|A" if same_row else "A",
    }
    task = preview(client, admin_headers, "albums", [row] if same_row else [row, row])
    expected_row = 2 if same_row else 3
    assert {(error["row"], error["field"]) for error in task["errors"]} == {
        (expected_row, "versions")
    }
    assert confirm(client, admin_headers, task).status_code == 422
    with SessionLocal() as db:
        assert (
            db.scalar(select(CatalogAlbum).where(CatalogAlbum.name == "Duplicate edition")) is None
        )


def test_existing_published_album_accepts_new_version_without_rewriting_parent_or_card(
    client, admin_headers
):
    album = create_album(
        client,
        admin_headers,
        name="Published shared work",
        artists=[{"type": "idols", "id": "idol-aria"}, {"type": "idols", "id": "idol-lin"}],
        versions=["Original"],
        release_date="2026-10-01",
        image_url="https://assets.example.test/original.webp",
        description="Original description",
    )
    original_version = versions(client, admin_headers, album["id"])["Original"]
    card_response = client.post(
        ROOT + "/cards",
        headers=admin_headers,
        json=payload(
            group_id=None, source_entity_id=album["id"], entity_version_id=original_version["id"]
        ),
    )
    assert card_response.status_code == 200, card_response.text
    card_id = card_response.json()["data"]["id"]
    for action in ["submit", "publish"]:
        response = client.post(
            ROOT + f"/entities/albums/{album['id']}/actions",
            headers=admin_headers,
            json={"action": action},
        )
        assert response.status_code == 200, response.text
    with SessionLocal() as db:
        before = db.get(CatalogAlbum, album["id"])
        original_fields = {
            field: getattr(before, field)
            for field in [
                "id",
                "name",
                "artist_name",
                "group_id",
                "release_date",
                "image_url",
                "description",
                "is_published",
            ]
        }
        card_data = dict(db.get(Card, card_id).admin_data)
    task = preview(
        client,
        admin_headers,
        "albums",
        [
            {
                "name": album["name"],
                "artist_names": "Lin|Aria",
                "versions": "Deluxe",
                "release_date": "2030-01-01",
                "image_url": "https://assets.example.test/replacement.webp",
                "description": "Replacement description",
            }
        ],
    )
    assert task["errors"] == []
    response = confirm(client, admin_headers, task)
    assert response.status_code == 200, response.text
    assert response.json()["data"]["rows"][0]["created_id"] == album["id"]
    with SessionLocal() as db:
        after = db.get(CatalogAlbum, album["id"])
        assert {field: getattr(after, field) for field in original_fields} == original_fields
        assert set(after.versions) == {"Original", "Deluxe"}
        assert album_artists(db, album["id"]) == {("idols", "idol-aria"), ("idols", "idol-lin")}
        meta = db.scalar(
            select(ContentMetadata).where(
                ContentMetadata.entity_id == album["id"], ContentMetadata.entity_type == "albums"
            )
        )
        assert meta.status == "PUBLISHED"
        assert db.get(Card, card_id).admin_data == card_data
    assert versions(client, admin_headers, album["id"])["Original"]["id"] == original_version["id"]
    duplicate = preview(
        client,
        admin_headers,
        "albums",
        [{"name": album["name"], "artist_names": "Aria|Lin", "versions": "Deluxe"}],
    )
    assert duplicate["rows"] == []
    assert duplicate["errors"][0]["field"] == "versions"


def test_same_album_name_with_different_artist_set_creates_distinct_works(client, admin_headers):
    task = preview(
        client,
        admin_headers,
        "albums",
        [
            {"name": "Shared title", "artist_names": "Aria", "versions": "A"},
            {"name": "Shared title", "artist_names": "Aria|Lin", "versions": "A"},
        ],
    )
    assert task["errors"] == []
    response = confirm(client, admin_headers, task)
    assert response.status_code == 200, response.text
    ids = {row["created_id"] for row in response.json()["data"]["rows"]}
    assert len(ids) == 2
    with SessionLocal() as db:
        artist_sets = {frozenset(album_artists(db, album_id)) for album_id in ids}
        assert artist_sets == {
            frozenset({("idols", "idol-aria")}),
            frozenset({("idols", "idol-aria"), ("idols", "idol-lin")}),
        }


def test_album_confirmation_rechecks_version_conflict_and_rolls_back_entire_batch(
    client, admin_headers
):
    existing = create_album(client, admin_headers, name="Concurrent edition work", versions=["A"])
    task = preview(
        client,
        admin_headers,
        "albums",
        [
            {"name": "Would be rolled back", "artist_names": "Aria", "versions": "First"},
            {"name": existing["name"], "artist_names": "Aria", "versions": "B"},
        ],
    )
    assert task["errors"] == []
    create_version(client, admin_headers, existing["id"], "B")
    response = confirm(client, admin_headers, task)
    assert response.status_code == 422, response.text
    assert {(error["row"], error["field"]) for error in response.json()["data"]["details"]} == {
        (3, "versions")
    }
    with SessionLocal() as db:
        assert (
            db.scalar(select(CatalogAlbum).where(CatalogAlbum.name == "Would be rolled back"))
            is None
        )
        assert (
            db.scalar(
                select(CatalogRecord).where(
                    CatalogRecord.kind == "versions",
                    CatalogRecord.data["name"].as_string() == "First",
                )
            )
            is None
        )
        assert db.get(AdminImportTask, task["id"]).status == "VALIDATED"
        assert set(db.get(CatalogAlbum, existing["id"]).versions) == {"A", "B"}


def test_album_version_record_crud_keeps_parent_names_consistent_and_references_protected(
    client, admin_headers
):
    album = create_album(client, admin_headers, versions=["A"])
    first = versions(client, admin_headers, album["id"])["A"]
    second = create_version(client, admin_headers, album["id"], "B")
    renamed = client.put(
        ROOT + f"/records/versions/{second['id']}",
        headers=admin_headers,
        json={"entity_type": "albums", "entity_id": album["id"], "data": {"name": "Deluxe"}},
    )
    assert renamed.status_code == 200, renamed.text
    assert renamed.json()["data"]["id"] == second["id"]
    with SessionLocal() as db:
        assert set(db.get(CatalogAlbum, album["id"]).versions) == {"A", "Deluxe"}
    card = client.post(
        ROOT + "/cards",
        headers=admin_headers,
        json=payload(group_id=None, source_entity_id=album["id"], entity_version_id=first["id"]),
    )
    assert card.status_code == 200, card.text
    assert (
        client.delete(ROOT + f"/records/versions/{first['id']}", headers=admin_headers).status_code
        == 409
    )
    assert (
        client.delete(ROOT + f"/records/versions/{second['id']}", headers=admin_headers).status_code
        == 200
    )
    with SessionLocal() as db:
        assert db.get(CatalogAlbum, album["id"]).versions == ["A"]
        meta = db.scalar(
            select(ContentMetadata).where(
                ContentMetadata.entity_type == "albums", ContentMetadata.entity_id == album["id"]
            )
        )
        assert meta.data["versions"] == ["A"]
        assert db.get(CatalogRecord, first["id"]) is not None
        assert db.get(CatalogRecord, second["id"]) is None
