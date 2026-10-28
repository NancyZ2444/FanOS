import io

import pytest
from sqlalchemy import func, select

from app.core.database import SessionLocal
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.models import UserCollectionItem


@pytest.mark.parametrize("selected_flow", [False, True])
@pytest.mark.parametrize("score", [0.72, 0.99])
def test_approximate_evidence_is_preserved_and_never_auto_recommended(
    client, auth_headers, scan_index, monkeypatch, selected_flow, score
):
    monkeypatch.setattr(
        CardMatcherAdapter,
        "rank",
        lambda *_: [
            {
                "card_id": "card-aria-01",
                "similarity": score,
                "feature_scores": {"approximate": 1.0, "inliers": 12.0},
            }
        ],
    )
    buffer = io.BytesIO()
    scan_index["card-aria-01"].save(buffer, format="JPEG")
    with SessionLocal() as db:
        count_before = db.scalar(select(func.sum(UserCollectionItem.quantity)))
    endpoint = "detect" if selected_flow else "recognize"
    response = client.post(
        f"/api/v1/scan/{endpoint}",
        headers=auth_headers,
        files={
            "image": ("card.jpg", buffer.getvalue(), "image/jpeg"),
        },
    )
    assert response.status_code == 200, response.text
    session = response.json()["data"]
    if selected_flow:
        response = client.post(
            f"/api/v1/scan/sessions/{session['session_id']}/recognize",
            headers=auth_headers,
            json={
                "detected_card_ids": [row["detected_card_id"] for row in session["detected_cards"]]
            },
        )
        assert response.status_code == 200, response.text
        session = response.json()["data"]
    row = session["detected_cards"][0]
    assert row["recognition_status"] == "needs_confirmation"
    assert row["candidates"][0]["scores"]["approximate"] == 1.0
    assert row["user_confirmed_card_id"] is None and not row["owned_added"]
    history = client.get("/api/v1/scan/history", headers=auth_headers).json()["data"]["items"][0]
    assert history["detected_cards"][0]["candidates"][0]["scores"]["approximate"] == 1.0
    with SessionLocal() as db:
        assert db.scalar(select(func.sum(UserCollectionItem.quantity))) == count_before
