from sqlalchemy import func, select

from app.admin_models import ContentMetadata
from app.core.database import SessionLocal
from app.models import Card
from app.modules.admin.catalog_extensions import CatalogRecord
from app.modules.catalog.tags import bind_tags
from app.modules.catalog.taxonomy_models import CatalogOther, CatalogTag, CatalogTagBinding
from app.modules.catalog.taxonomy_upgrade import migrate_taxonomy

ROOT = "/api/v1/admin/console"
PUBLIC = "/api/v1/catalog"


def post(client, headers, path, data):
    r = client.post(path, headers=headers, json=data)
    assert r.status_code == 200, r.text
    return r.json()["data"]


def create(client, headers, name, tags=()):
    return post(
        client,
        headers,
        ROOT + "/entities/others",
        {"name": name, "original_name": "Original", "start_date": "2026-10-11", "tags": list(tags)},
    )


def publish(client, headers, kind, id):
    for action in ["submit", "publish"]:
        post(client, headers, ROOT + f"/entities/{kind}/{id}/actions", {"action": action})


def tag_list(client, headers):
    return client.get(ROOT + "/tags", headers=headers).json()["data"]["items"]


def test_scoped_normalized_tags_and_usage(client, admin_headers):
    first = create(client, admin_headers, "One", ["Lucky  Draw", "lucky draw", "ＬＵＣＫＹ Draw"])
    second = create(client, admin_headers, "Two", [" lucky draw "])
    assert len(first["tag_ids"]) == 1 and first["tag_ids"] == second["tag_ids"]
    other = post(
        client, admin_headers, ROOT + "/tags", {"entity_type": "ALBUM", "name": "Lucky Draw"}
    )
    assert other["id"] != first["tag_ids"][0]
    detail = next(t for t in tag_list(client, admin_headers) if t["id"] == first["tag_ids"][0])
    assert detail["usage_count"] == 2 and detail["source"] == "INTERNAL"
    rows = client.get(ROOT + f"/tags/{detail['id']}/contents", headers=admin_headers).json()[
        "data"
    ]["items"]
    assert {r["id"] for r in rows} == {first["id"], second["id"]}
    assert (
        client.post(
            ROOT + "/entities/collections", headers=admin_headers, json={"name": "retired"}
        ).status_code
        == 404
    )
    assert (
        client.post(
            ROOT + "/entities/merchandise", headers=admin_headers, json={"name": "retired"}
        ).status_code
        == 404
    )


def test_disable_rename_preserves_history_but_blocks_new_bindings(client, admin_headers):
    item = create(client, admin_headers, "One", ["POB"])
    tag = item["tag_ids"][0]
    r = client.put(
        ROOT + "/tags/" + tag,
        headers=admin_headers,
        json={"name": "Pre Order", "status": "DISABLED"},
    )
    assert r.status_code == 200, r.text
    assert not any(
        t["id"] == tag
        for t in client.get(PUBLIC + "/tags?entity_type=OTHER").json()["data"]["items"]
    )
    assert (
        client.post(
            ROOT + "/entities/others",
            headers=admin_headers,
            json={"name": "New", "tags": ["pre order"]},
        ).status_code
        == 422
    )
    r = client.put(
        ROOT + "/entities/others/" + item["id"],
        headers=admin_headers,
        json={"name": "One", "tags": ["Pre Order"]},
    )
    assert r.status_code == 200, r.text
    assert r.json()["data"]["tag_ids"] == [tag]
    publish(client, admin_headers, "others", item["id"])
    data = client.get(PUBLIC + "/others/" + item["id"]).json()["data"]
    assert data["tags"] == ["Pre Order"] and data["tag_details"][0]["status"] == "DISABLED"
    with SessionLocal() as db:
        before = db.scalar(select(func.count()).select_from(CatalogTag))
        assert migrate_taxonomy(db) == {
            "others_created": 0,
            "card_sources_updated": 0,
            "tagged_entities": 0,
        }
        db.commit()
        assert db.scalar(select(func.count()).select_from(CatalogTag)) == before


def test_contributions_subject_and_tags_share_one_review(client, admin_headers, auth_headers):
    def submit(name):
        return post(
            client,
            auth_headers,
            PUBLIC + "/feedback",
            {
                "entity_type": "others",
                "reason": "公开资料补充",
                "suggested": {
                    "name": name,
                    "original_name": "Original",
                    "start_date": "2026-01-01",
                    "end_date": "2026-02-01",
                    "description": "Details",
                    "tags": ["Brand  Collaboration"],
                },
            },
        )

    rejected = submit("Rejected")
    accepted = submit("Accepted")
    concurrent = submit("Second")
    assert not any(t["name"] == "Brand Collaboration" for t in tag_list(client, admin_headers))
    post(
        client,
        admin_headers,
        ROOT + f"/review-queue/contribution/{rejected['id']}/actions",
        {"action": "reject", "reason": "无法验证"},
    )
    assert not any(t["name"] == "Brand Collaboration" for t in tag_list(client, admin_headers))
    for item in [accepted, concurrent]:
        post(
            client,
            admin_headers,
            ROOT + f"/review-queue/contribution/{item['id']}/actions",
            {"action": "accept"},
        )
    tags = [t for t in tag_list(client, admin_headers) if t["name"] == "Brand Collaboration"]
    assert len(tags) == 1 and tags[0]["usage_count"] == 2 and tags[0]["source"] == "USER_SUBMITTED"
    assert tags[0]["submission_id"] == accepted["id"]
    published = client.get(PUBLIC + "/others?q=Accepted").json()["data"]["items"]
    assert len(published) == 1 and published[0]["tags"] == ["Brand Collaboration"]
    with SessionLocal() as db:
        review = db.get(CatalogRecord, rejected["id"])
        assert not review.entity_id
        assert not db.scalar(select(CatalogOther).where(CatalogOther.name == "Rejected"))


def test_failed_approval_rolls_back_tags_and_subject(client, admin_headers, auth_headers):
    review = post(
        client,
        auth_headers,
        PUBLIC + "/feedback",
        {
            "entity_type": "cards",
            "reason": "缺失小卡",
            "suggested": {
                "title": "Incomplete",
                "group_id": "group-lumina",
                "idol_id": "idol-aria",
                "tags": ["Approval Rollback"],
            },
        },
    )
    r = client.post(
        ROOT + f"/review-queue/contribution/{review['id']}/actions",
        headers=admin_headers,
        json={"action": "accept"},
    )
    assert r.status_code == 422, r.text
    with SessionLocal() as db:
        assert db.get(CatalogRecord, review["id"]).status == "PENDING"
        assert not db.scalar(select(CatalogTag).where(CatalogTag.name == "Approval Rollback"))
        assert not db.scalar(select(Card).where(Card.title == "Incomplete"))


def test_dynamic_facets_apply_context_before_pagination(client):
    with SessionLocal() as db:
        cards = db.scalars(select(Card).where(Card.status == "PUBLISHED")).all()
        target = cards[0]
        target_id = target.id
        target_group = target.group_id
        target_idol = target.idol_id
        other = next(c for c in cards if c.group_id != target_group)
        bind_tags(db, "cards", target.id, ["Only This Context", "Common"], "legacy")
        bind_tags(db, "cards", other.id, ["Unrelated"], "legacy")
        target.admin_data = {
            **(target.admin_data or {}),
            "source_entity_type": "OTHER",
            "source_entity_id": "merch-afterglow-shirt",
        }
        db.commit()
    r = client.get(
        PUBLIC + "/cards",
        params={
            "group_id": target_group,
            "idol_id": target_idol,
            "source_entity_type": "OTHER",
            "limit": 1,
        },
    ).json()["data"]
    assert r["items"][0]["id"] == target_id
    assert {t["name"] for t in r["available_tags"]} == {"Only This Context", "Common"}
    unrelated = client.get(PUBLIC + "/cards", params={"q": "no such title"}).json()["data"]
    assert unrelated["available_tags"] == []
    tag = r["available_tags"][0]["id"]
    assert client.get(PUBLIC + "/cards", params={"tag_ids": tag}).json()["data"]["total"] == 1


def test_other_dates_fields_and_user_system_field_rejection(client, admin_headers, auth_headers):
    assert (
        client.post(
            ROOT + "/entities/others",
            headers=admin_headers,
            json={"name": "Dates", "start_date": "2026-10-11", "end_date": "2026-01-01"},
        ).status_code
        == 422
    )
    for suggested in [
        {"name": "Injected", "status": "PUBLISHED"},
        {"name": "Bad dates", "start_date": "2026.01.01"},
        {"name": "Bad tags", "tags": ["   "]},
    ]:
        assert (
            client.post(
                PUBLIC + "/feedback",
                headers=auth_headers,
                json={"entity_type": "others", "reason": "test", "suggested": suggested},
            ).status_code
            == 422
        )
    assert (
        client.post(
            PUBLIC + "/feedback",
            headers=auth_headers,
            json={
                "entity_type": "cards",
                "reason": "test",
                "suggested": {"source_entity_type": "MERCHANDISE"},
            },
        ).status_code
        == 422
    )


def test_legacy_copy_preserves_ids_refs_snapshot_and_is_repeat_safe(client):
    from app.admin_models import CatalogCollection

    with SessionLocal() as db:
        db.delete(db.get(CatalogRecord, "taxonomy-20261011"))
        db.flush()
        db.add(
            CatalogCollection(
                id="legacy-collection",
                name="Legacy",
                group_id="group-lumina",
                release_date="2026.01.02",
                description="Original",
            )
        )
        db.add(
            ContentMetadata(
                entity_type="collections",
                entity_id="legacy-collection",
                status="PUBLISHED",
                operator_id="legacy",
                data={"tags": ["Legacy Tag"], "custom_field": "Retain me"},
            )
        )
        card = db.get(Card, "card-aria-01")
        card.admin_data = {
            **(card.admin_data or {}),
            "source_entity_type": "COLLECTION",
            "source_entity_id": "legacy-collection",
        }
        db.flush()
        migrate_taxonomy(db)
        db.commit()
        other = db.get(CatalogOther, "legacy-collection")
        assert other.name == "Legacy" and other.start_date == "2026-01-02" and other.is_published
        assert other.legacy_data["metadata"]["custom_field"] == "Retain me"
        assert other.group_id == "group-lumina"
        assert (
            card.admin_data["source_entity_type"] == "OTHER"
            and card.admin_data["source_entity_id"] == other.id
        )
        meta = db.scalar(select(ContentMetadata).where(ContentMetadata.entity_id == other.id))
        assert meta.entity_type == "others" and meta.status == "PUBLISHED"
        tag = db.scalar(select(CatalogTag).where(CatalogTag.name == "Legacy Tag"))
        tag.name = "Renamed"
        tag.normalized_name = "renamed"
        db.commit()
        migrate_taxonomy(db)
        db.commit()
        assert not db.scalar(select(CatalogTag).where(CatalogTag.name == "Legacy Tag"))
        assert (
            db.scalar(
                select(func.count())
                .select_from(CatalogTagBinding)
                .where(CatalogTagBinding.entity_id == other.id)
            )
            == 1
        )
