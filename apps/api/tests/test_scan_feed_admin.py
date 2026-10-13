from __future__ import annotations

import io
import json

from PIL import Image


def _image_bytes() -> bytes:
    image = Image.new("RGB", (600, 900), (178, 164, 224))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG")
    return buffer.getvalue()


def test_scan_recognize_confirm_and_feedback(client, auth_headers, scan_index):
    status = client.get("/api/v1/scan/status")
    assert status.status_code == 200
    assert "indexed_card_count" in status.json()["data"]
    assert "missing_requirements" in status.json()["data"]

    image_buffer = io.BytesIO()
    scan_index["card-aria-01"].save(image_buffer, format="JPEG")
    scan = client.post(
        "/api/v1/scan/recognize",
        headers=auth_headers,
        files={"image": ("cards.jpg", image_buffer.getvalue(), "image/jpeg")},
    )
    assert scan.status_code == 200, scan.text
    session = scan.json()["data"]
    assert len(session["detected_cards"]) >= 1
    detected = session["detected_cards"][0]
    assert detected["candidates"][0]["card"]["id"] == "card-aria-01"
    card_id = detected["candidates"][0]["card"]["id"]

    confirmed = client.post(
        f"/api/v1/scan/sessions/{session['session_id']}/confirm",
        headers=auth_headers,
        json={"cards": [{"detected_card_id": detected["detected_card_id"], "card_id": card_id}]},
    )
    assert confirmed.json()["data"]["added_count"] == 1

    metadata = {
        "scan_session_id": session["session_id"],
        "detected_card_id": detected["detected_card_id"],
        "crop_region": detected["crop_region"],
        "ai_candidates": [],
        "notes": "需要人工确认",
    }
    feedback = client.post(
        "/api/v1/scan/feedback",
        headers=auth_headers,
        data={"metadata": json.dumps(metadata)},
    )
    assert feedback.status_code == 200
    assert feedback.json()["data"]["feedback_id"].startswith("feedback_")


def test_feed_interactions_and_admin_worker_ingestion(client, auth_headers, admin_headers):
    feed = client.get("/api/v1/idol-feed?limit=20").json()["data"]
    assert len(feed["items"]) == 20
    assert feed["next_cursor"] == "20"

    liked = client.put("/api/v1/idol-feed/feed-1/like", headers=auth_headers)
    assert liked.json()["data"]["liked"] is True
    comment = client.post(
        "/api/v1/idol-feed/feed-1/comments",
        headers=auth_headers,
        json={"content": "期待正式舞台"},
    ).json()["data"]
    assert comment["is_mine"] is True
    assert (
        client.delete(f"/api/v1/comments/{comment['id']}", headers=auth_headers).status_code == 200
    )

    worker_post = {
        "platform": "weibo",
        "original_post_id": "worker-unique-1",
        "idol_id": "idol-aria",
        "group_id": "group-lumina",
        "post_time": "2026-09-15T10:00:00Z",
        "content": "Worker 导入动态",
        "media": [],
        "original_url": "https://weibo.com/demo",
        "fetch_time": "2026-09-15T10:01:00Z",
    }
    ingested = client.post(
        "/api/v1/admin/worker/social-posts:upsert",
        headers={"X-Worker-Token": "fan-os-dev-worker-token"},
        json={"items": [worker_post]},
    )
    assert ingested.json()["data"] == {"created": 1, "updated": 0}
    repeated = client.post(
        "/api/v1/admin/worker/social-posts:upsert",
        headers={"X-Worker-Token": "fan-os-dev-worker-token"},
        json={"items": [worker_post]},
    )
    assert repeated.json()["data"] == {"created": 0, "updated": 1}
    assert client.get("/api/v1/admin/cards", headers=admin_headers).status_code == 200
