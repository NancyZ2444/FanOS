"""Explicit album normalization is additive, audited and safe to repeat."""

import copy

import pytest
from sqlalchemy import select

from app.admin_models import ContentMetadata
from app.core.database import SessionLocal
from app.models import Card, CatalogAlbum, OperationLog
from app.modules.admin.album_normalization import NORMALIZATION, normalize_albums
from app.modules.admin.catalog_extensions import CatalogRecord
from app.modules.admin.catalog_service import meta_for, row_data

ROOT = "/api/v1/admin/console"
COLLABORATORS = [{"type": "idols", "id": "idol-aria"}, {"type": "idols", "id": "idol-lin"}]


def family(db, suffix="one"):
    work = "Approved work " + suffix
    sources = [("normalization-parent-" + suffix, "A"), ("normalization-alias-" + suffix, "B")]
    for album_id, edition in sources:
        title = f"{work} — {edition}"
        db.add(
            CatalogAlbum(
                id=album_id,
                name=title,
                name_en=title,
                artist_name="Aria / Lin",
                group_id="group-lumina",
                release_date="2026-10-01",
                album_type="Collaboration",
                versions=[],
                description="Edition " + edition + " description",
                image_url=f"https://assets.example.test/{suffix}-{edition}.webp",
                front_image_url=f"https://assets.example.test/{suffix}-{edition}-front.webp",
                back_image_url=f"https://assets.example.test/{suffix}-{edition}-back.webp",
                is_published=False,
            )
        )
        db.add(
            ContentMetadata(
                entity_type="albums",
                entity_id=album_id,
                status="DRAFT",
                operator_id="admin-test",
                data={
                    "name": title,
                    "name_en": title,
                    "artists": copy.deepcopy(COLLABORATORS),
                    "versions": [],
                    "source_info": {
                        "source_type": "OFFICIAL",
                        "source_url": f"https://official.example.test/{suffix}/{edition}",
                        "copyright_status": "AUTHORIZED",
                        "copyright_note": "Original source " + edition,
                    },
                    "tags": ["Original", edition],
                },
            )
        )
    db.commit()
    return {"name": work, "parent_id": sources[0][0], "sources": sources}


def snapshot(db, album_ids):
    return {
        "albums": [
            row_data(row)
            for row in db.scalars(
                select(CatalogAlbum).where(CatalogAlbum.id.in_(album_ids)).order_by(CatalogAlbum.id)
            )
        ],
        "metadata": [
            row_data(row)
            for row in db.scalars(
                select(ContentMetadata)
                .where(
                    ContentMetadata.entity_type == "albums",
                    ContentMetadata.entity_id.in_(album_ids),
                )
                .order_by(ContentMetadata.id)
            )
        ],
        "versions": [
            row_data(row)
            for row in db.scalars(
                select(CatalogRecord)
                .where(CatalogRecord.kind == "versions")
                .order_by(CatalogRecord.id)
            )
        ],
        "audits": [
            row_data(row) for row in db.scalars(select(OperationLog).order_by(OperationLog.id))
        ],
    }


def test_normalization_preview_has_complete_mapping_and_never_writes():
    with SessionLocal() as db:
        approved = family(db)
        ids = [album_id for album_id, _ in approved["sources"]]
        before = snapshot(db, ids)
        report = normalize_albums(db, families=[approved], legacy_ids=[])
        assert report["applied"] is False
        assert report["normalization"] == NORMALIZATION
        assert len(report["mappings"]) == len(report["versions_created"]) == 2
        assert {mapping["old_id"] for mapping in report["mappings"]} == set(ids)
        assert {mapping["parent_id"] for mapping in report["mappings"]} == {approved["parent_id"]}
        assert {mapping["version_name"] for mapping in report["mappings"]} == {"A", "B"}
        assert all(mapping["version_id"].startswith("planned:") for mapping in report["mappings"])
        assert not db.new and not db.dirty and not db.deleted
        db.commit()
        assert snapshot(db, ids) == before


def test_normalization_keeps_source_ids_and_snapshots_of_artists_images_and_rights():
    with SessionLocal() as db:
        approved = family(db)
        parent_id, alias_id = [album_id for album_id, _ in approved["sources"]]
        before = {
            album_id: {
                "album": copy.deepcopy(row_data(db.get(CatalogAlbum, album_id))),
                "metadata": copy.deepcopy(row_data(meta_for(db, "albums", album_id))),
            }
            for album_id in [parent_id, alias_id]
        }
        report = normalize_albums(db, apply=True, families=[approved], legacy_ids=[])
        db.commit()
        parent = db.get(CatalogAlbum, parent_id)
        parent_meta = meta_for(db, "albums", parent_id)
        alias = db.get(CatalogAlbum, alias_id)
        alias_meta = meta_for(db, "albums", alias_id)
        assert parent.name == parent.name_en == approved["name"]
        assert parent.versions == parent_meta.data["versions"] == ["A", "B"]
        assert parent_meta.status == "DRAFT" and not parent.is_published
        assert parent_meta.data["artists"] == COLLABORATORS
        assert parent.image_url == before[parent_id]["album"]["image_url"]
        assert parent.release_date == before[parent_id]["album"]["release_date"]
        assert row_data(alias) == before[alias_id]["album"]
        assert alias_meta.status == "ARCHIVED"
        assert alias_meta.data["merged_into"] == parent_id
        assert alias_meta.data["artists"] == COLLABORATORS
        assert alias_meta.data["source_info"] == before[alias_id]["metadata"]["data"]["source_info"]
        assert len(report["mappings"]) == 2
        for mapping in report["mappings"]:
            original = before[mapping["old_id"]]
            record = db.get(CatalogRecord, mapping["version_id"])
            assert record.kind == "versions" and record.entity_type == "albums"
            assert record.entity_id == parent_id
            assert record.data["name"] == mapping["version_name"]
            assert record.data["original_album_id"] == mapping["old_id"]
            assert record.data["original_snapshot"] == original
            assert record.data["source_info"] == original["metadata"]["data"]["source_info"]
            for image_field in ["image_url", "front_image_url", "back_image_url"]:
                assert record.data[image_field] == original["album"][image_field]
        archived_mapping = next(
            mapping for mapping in report["mappings"] if mapping["old_id"] == alias_id
        )
        assert alias_meta.data["merged_version_id"] == archived_mapping["version_id"]
        assert parent_meta.data["album_normalization"]["mappings"] == report["mappings"]
        audit_actions = [log.action for log in db.scalars(select(OperationLog)).all()]
        assert audit_actions.count("catalog.album.normalize_version") == 2
        assert audit_actions.count("catalog.album.archive_mapping") == 1
        assert audit_actions.count("catalog.album.normalize_parent") == 1


def test_normalization_repeat_is_idempotent_for_records_mappings_and_audit():
    with SessionLocal() as db:
        approved = family(db)
        ids = [album_id for album_id, _ in approved["sources"]]
        original_report = normalize_albums(db, apply=True, families=[approved], legacy_ids=[])
        db.commit()
        before_repeat = snapshot(db, ids)
        repeated = normalize_albums(db, apply=True, families=[approved], legacy_ids=[])
        db.commit()
        assert repeated["mappings"] == original_report["mappings"]
        assert repeated["versions_created"] == repeated["legacy_versions_created"] == []
        assert repeated["families"][0]["already_applied"] is True
        assert snapshot(db, ids) == before_repeat


@pytest.mark.parametrize(
    "conflict", ["card_reference", "json_reference", "artists", "published", "ever_published"]
)
def test_normalization_rejects_entire_plan_before_writing_if_any_family_is_unsafe(conflict):
    with SessionLocal() as db:
        first = family(db, "first")
        second = family(db, "unsafe")
        unsafe_id = second["sources"][1][0]
        meta = meta_for(db, "albums", unsafe_id)
        if conflict == "card_reference":
            card = db.get(Card, "card-aria-01")
            card.admin_data = {**card.admin_data, "source_entity_id": unsafe_id}
        elif conflict == "json_reference":
            db.add(
                CatalogRecord(
                    kind="reviews",
                    entity_type="cards",
                    entity_id="card-aria-01",
                    data={"suggestion": {"source_entity_id": unsafe_id}},
                )
            )
        elif conflict == "artists":
            meta.data = {**meta.data, "artists": [{"type": "idols", "id": "idol-aria"}]}
        elif conflict == "published":
            meta.status = "PUBLISHED"
            db.get(CatalogAlbum, unsafe_id).is_published = True
        elif conflict == "ever_published":
            meta.data = {**meta.data, "ever_published": True}
        db.commit()
        all_ids = [album_id for item in [first, second] for album_id, _ in item["sources"]]
        before = snapshot(db, all_ids)
        with pytest.raises(ValueError):
            normalize_albums(db, apply=True, families=[first, second], legacy_ids=[])
        assert not db.new and not db.dirty and not db.deleted
        db.commit()
        assert snapshot(db, all_ids) == before


@pytest.mark.parametrize("with_metadata", [False, True])
def test_legacy_materialization_keeps_existing_version_id_and_content_while_adding_only_missing(
    with_metadata,
):
    with SessionLocal() as db:
        album = db.get(CatalogAlbum, "album-starlit")
        first_name, second_name = album.versions
        if with_metadata:
            db.add(
                ContentMetadata(
                    entity_type="albums",
                    entity_id=album.id,
                    status="PUBLISHED",
                    operator_id="legacy-test",
                    data={"versions": album.versions, "note": "Original legacy metadata"},
                )
            )
        existing = CatalogRecord(
            id="normalization-existing-version",
            kind="versions",
            entity_type="albums",
            entity_id=album.id,
            status="DRAFT",
            data={
                "name": first_name,
                "code": "KEEP",
                "image_url": "https://assets.example.test/independent.webp",
                "source_info": {"copyright_status": "AUTHORIZED"},
                "custom": "existing detail",
            },
        )
        db.add(existing)
        db.commit()
        existing_before = copy.deepcopy(row_data(existing))
        parent_before = snapshot(db, [album.id])
        preview = normalize_albums(db, families=[], legacy_ids=[album.id])
        assert len(preview["legacy_versions_created"]) == 1
        db.commit()
        assert snapshot(db, [album.id]) == parent_before
        report = normalize_albums(db, apply=True, families=[], legacy_ids=[album.id])
        db.commit()
        assert len(report["legacy_versions_created"]) == 1
        assert row_data(db.get(CatalogRecord, existing.id)) == existing_before
        created = db.get(CatalogRecord, report["legacy_versions_created"][0])
        assert created.data["name"] == second_name
        assert created.entity_id == album.id and created.entity_type == "albums"
        assert row_data(album) == parent_before["albums"][0]
        if with_metadata:
            assert row_data(meta_for(db, "albums", album.id)) == parent_before["metadata"][0]
        else:
            assert meta_for(db, "albums", album.id) is None
        before_repeat = snapshot(db, [album.id])
        repeat = normalize_albums(db, apply=True, families=[], legacy_ids=[album.id])
        db.commit()
        assert repeat["legacy_versions_created"] == []
        assert snapshot(db, [album.id]) == before_repeat


def test_normalized_alias_and_mapped_version_are_protected_through_admin_api(client, admin_headers):
    with SessionLocal() as db:
        approved = family(db)
        alias_id = approved["sources"][1][0]
        report = normalize_albums(db, apply=True, families=[approved], legacy_ids=[])
        db.commit()
        version_id = next(
            item["version_id"] for item in report["mappings"] if item["old_id"] == alias_id
        )
        ids = [album_id for album_id, _ in approved["sources"]]
        before = snapshot(db, ids)
    restore = client.post(
        ROOT + f"/entities/albums/{alias_id}/actions",
        headers=admin_headers,
        json={"action": "restore"},
    )
    detach = client.post(ROOT + f"/detach/albums/{alias_id}", headers=admin_headers)
    delete_alias = client.delete(ROOT + f"/entities/albums/{alias_id}", headers=admin_headers)
    delete_version = client.delete(ROOT + f"/records/versions/{version_id}", headers=admin_headers)
    assert (
        restore.status_code
        == detach.status_code
        == delete_alias.status_code
        == delete_version.status_code
        == 409
    )
    detail = client.get(ROOT + f"/entities/albums/{alias_id}/detail", headers=admin_headers)
    assert detail.status_code == 200
    with SessionLocal() as db:
        assert snapshot(db, ids) == before
        assert meta_for(db, "albums", alias_id).status == "ARCHIVED"
        assert db.get(CatalogRecord, version_id).entity_id == approved["parent_id"]
