from sqlalchemy import select

from app.core.database import SessionLocal
from app.models import DetectedCard, ScanSession, UserCollectionItem, UserWishlistItem


def test_original_scan_ensure_owned_is_idempotent_across_objects_and_preserves_wishlist(
    client, auth_headers, second_app_headers
):
    with SessionLocal() as db:
        session = ScanSession(user_id="current-user", original_image_url="/media/test-only.png")
        db.add(session)
        db.flush()
        objects = [
            DetectedCard(
                scan_session_id=session.id, crop_region={}, recognition_status="unrecognized",
                crop_image_url="/media/test-only-crop.png",
            )
            for _ in range(2)
        ]
        db.add_all(objects)
        db.commit()
        session_id, ids = session.id, [obj.id for obj in objects]
        before = db.scalar(
            select(UserCollectionItem).where(
                UserCollectionItem.user_id == "current-user",
                UserCollectionItem.card_id == "card-aria-01",
            )
        )
        if before:
            db.delete(before)
            db.commit()

    endpoint = f"/api/v1/scan/sessions/{session_id}/confirm"
    body = {
        "cards": [
            {
                "detected_card_id": item,
                "card_id": "card-aria-01",
                "selected": False,
                "ensure_owned": True,
                "add_to_wishlist": True,
            }
            for item in ids
        ]
    }
    assert client.post(endpoint, headers=second_app_headers, json=body).status_code == 404
    for attempt in range(2):
        response = client.post(endpoint, headers=auth_headers, json=body)
        assert response.status_code == 200, response.text
        assert response.json()["data"] == {
            "added_count": 1 if attempt == 0 else 0,
            "quantities": {"card-aria-01": 1},
        }
    with SessionLocal() as db:
        owned = db.scalar(
            select(UserCollectionItem).where(
                UserCollectionItem.user_id == "current-user",
                UserCollectionItem.card_id == "card-aria-01",
            )
        )
        owned.quantity = 3
        db.commit()
    response = client.post(endpoint, headers=auth_headers, json=body)
    assert response.json()["data"]["quantities"] == {"card-aria-01": 3}
    # Changing a confirmed association does not move an already saved relation.
    body["cards"] = [{"detected_card_id": ids[0], "card_id": "card-mina-01", "selected": False}]
    response = client.post(endpoint, headers=auth_headers, json=body)
    assert response.status_code == 200, response.text
    with SessionLocal() as db:
        assert (
            db.scalar(
                select(UserCollectionItem).where(
                    UserCollectionItem.user_id == "current-user",
                    UserCollectionItem.card_id == "card-aria-01",
                )
            ).quantity
            == 3
        )
        assert (
            db.scalar(
                select(UserWishlistItem).where(
                    UserWishlistItem.user_id == "current-user",
                    UserWishlistItem.card_id == "card-aria-01",
                )
            )
            is not None
        )
