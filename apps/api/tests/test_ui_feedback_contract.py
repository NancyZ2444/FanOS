from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import select
from test_feedback_workflow import action, result, upload

from app.core.database import SessionLocal
from app.models import Card
from app.modules.albums.schemas import CanvasConfig, Element


def test_card_feedback_only_visible_objective_fields(client, auth_headers):
    with SessionLocal() as db:
        card_id = db.scalar(select(Card.id).where(Card.status == "PUBLISHED"))
    obj = client.get(f"/api/v1/feedback/objects/cards/{card_id}", headers=auth_headers).json()[
        "data"
    ]
    fields = {f["key"]: f for f in obj["fields"]}
    assert set(fields) == {
        "idol_id",
        "group_id",
        "source_entity_id",
        "entity_version_id",
        "image_url",
        "back_image_url",
        "card_type",
        "release_date",
        "region",
    }
    for key in ("idol_id", "group_id", "source_entity_id"):
        if fields[key]["current"]:
            assert fields[key]["current_display"]
            assert fields[key]["current_display"] != fields[key]["current"]
    for forbidden in (
        "title",
        "card_number",
        "is_double_sided",
        "is_group_pc",
        "source_entity_type",
    ):
        response = client.post(
            "/api/v1/feedback",
            headers=auth_headers,
            json={
                "request_key": str(uuid4()),
                "kind": "CORRECTION",
                "entity_type": "cards",
                "entity_id": card_id,
                "object_version": obj["version"],
                "fields": [{"key": forbidden, "mode": "UNKNOWN", "reason": "该字段不可反馈"}],
            },
        )
        assert response.status_code == 422


def test_cover_strokes_persist_normalized_points_without_raster_export():
    stroke = Element(
        id="stroke",
        type="STROKE",
        width=1,
        height=1,
        points=[(0.1, 0.2), (0.8, 0.7)],
        style={"stroke_width": 3, "color": "#6D5DD3"},
    )
    canvas = CanvasConfig(elements=[stroke])
    assert CanvasConfig.model_validate(canvas.model_dump()).elements[0].points == stroke.points
    for points in ([], [(0, 0)], [(0, 0), (2, 0)], [(0, 0)] * 513):
        with pytest.raises(ValidationError):
            Element(id="bad", type="STROKE", points=points)


def test_clear_legacy_version_does_not_reappear(client, auth_headers, admin_headers):
    image = upload(client, auth_headers)
    with SessionLocal() as db:
        card = db.scalar(select(Card).where(Card.idol_id == "idol-aria"))
        card.version = "Legacy edition"
        card.image_url = image["image_url"]
        card.admin_data = {
            **(card.admin_data or {}),
            "entity_version_id": None,
            "source_entity_type": "ALBUM",
            "source_entity_id": "album-starlit",
            "front_source": {"source_type": "USER_SUBMITTED", "copyright_status": "AUTHORIZED"},
        }
        card_id = card.id
        db.commit()
    obj = result(client.get(f"/api/v1/feedback/objects/cards/{card_id}", headers=auth_headers))
    row = result(
        client.post(
            "/api/v1/feedback",
            headers=auth_headers,
            json={
                "request_key": str(uuid4()),
                "kind": "CORRECTION",
                "entity_type": "cards",
                "entity_id": card_id,
                "object_version": obj["version"],
                "fields": [{"key": "entity_version_id", "mode": "CLEAR", "reason": "无独立版本"}],
            },
        )
    )
    published = result(
        action(
            client,
            admin_headers,
            row,
            "publish",
            object_version=obj["version"],
            decisions=[{"key": "entity_version_id", "decision": "ACCEPT"}],
        )
    )
    assert published["result"] == "INCLUDED"
    assert published["decisions"][0]["value_display"] == ""
    with SessionLocal() as db:
        assert db.get(Card, card_id).version == ""
