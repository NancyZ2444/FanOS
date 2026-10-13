#!/usr/bin/env python3
"""Exercise real indexed artwork through ASGI on an isolated SQLite snapshot.

No TCP socket or changes to users' collections are required. This tests repeat
photos and synthetic transformations, not real-camera field accuracy.
"""

from __future__ import annotations

import argparse
import io
import json
import sqlite3
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageEnhance

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def main():
    from app.core.config import get_settings

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("../../output/scan-verification"))
    args = parser.parse_args()
    settings = get_settings()
    if not settings.database_url.startswith("sqlite:///") or settings.storage_backend != "local":
        raise SystemExit("This local verification command requires SQLite and local media.")
    original_db = settings.database_url.removeprefix("sqlite:///")
    with sqlite3.connect(original_db) as source:
        row = source.execute(
            "SELECT id, image_url FROM cards WHERE status='PUBLISHED' "
            "AND image_url IS NOT NULL ORDER BY id LIMIT 1"
        ).fetchone()
        if row is None:
            raise SystemExit("Upload and index a card front first.")
        card_id, url = row
        prefix = settings.public_media_base_url.rstrip("/") + "/"
        if not url.startswith(prefix):
            raise SystemExit("Card front is not in configured local storage.")
        root = settings.local_media_root.resolve()
        path = (root / url.removeprefix(prefix)).resolve()
        if not path.is_relative_to(root):
            raise SystemExit("Invalid image path.")
        photo = Image.open(path).convert("RGB")
        with tempfile.TemporaryDirectory(prefix="fanos-scan-test-") as temporary:
            isolated = Path(temporary)
            with sqlite3.connect(isolated / "api.db") as destination:
                source.backup(destination)
            settings.database_url = f"sqlite:///{isolated / 'api.db'}"
            settings.local_media_root = isolated / "media"
            settings.local_media_root.mkdir()
            settings.auto_seed = False

            from fastapi.testclient import TestClient

            from app.integrations.card_matcher.adapter import CardMatcherAdapter
            from app.main import app

            report = {
                "scope": "existing uploaded image + synthetic transformations; no camera capture",
                "card_id": card_id,
                "cases": [],
            }
            encoded = io.BytesIO()
            photo.save(encoded, format="PNG")
            crop = CardMatcherAdapter.detect(encoded.getvalue())[0].crop
            crop.thumbnail((360, 520))
            multi = Image.new("RGB", (crop.width * 3 + 160, crop.height + 100), "#202020")
            for i in range(2):
                multi.paste(crop, (40 + i * (crop.width + 40), 50))
            multi.paste(Image.new("RGB", crop.size, "white"), (40 + 2 * (crop.width + 40), 50))
            cases = [
                ("original", photo, 1),
                ("rotated_90", photo.rotate(90, expand=True), 1),
                ("crop_darker", ImageEnhance.Brightness(crop).enhance(0.75), 1),
                ("two_same_one_unknown", multi, 2),
                ("all_unknown", Image.new("RGB", crop.size, "white"), 0),
            ]
            args.output.mkdir(parents=True, exist_ok=True)
            multi.save(args.output / "multi-card-input.jpg")
            with TestClient(app) as client:
                token = client.post(
                    "/api/v1/auth/login",
                    json={
                        "method": "phone",
                        "phone": "13800000000",
                        "code": settings.dev_phone_code,
                    },
                ).json()["data"]["access_token"]
                headers = {"Authorization": f"Bearer {token}"}
                report["readiness"] = client.get("/api/v1/scan/status").json()["data"]
                for name, image, expected in cases:
                    buffer = io.BytesIO()
                    image.save(buffer, format="JPEG", quality=85)
                    response = client.post(
                        "/api/v1/scan/recognize",
                        headers=headers,
                        files={"image": ("photo.jpg", buffer.getvalue(), "image/jpeg")},
                    )
                    assert response.status_code == 200, response.text
                    session = response.json()["data"]
                    detected = session["detected_cards"]
                    matched = [
                        d
                        for d in detected
                        if d["candidates"] and d["candidates"][0]["card"]["id"] == card_id
                    ]
                    assert len(matched) == expected, (name, detected)
                    result = {
                        "case": name,
                        "detected": len(detected),
                        "matched": len(matched),
                        "statuses": [d["recognition_status"] for d in detected],
                        "top_scores": [
                            d["candidates"][0]["similarity"] if d["candidates"] else None
                            for d in detected
                        ],
                    }
                    if name == "two_same_one_unknown":
                        payload = {
                            "cards": [
                                {"detected_card_id": d["detected_card_id"], "card_id": card_id}
                                for d in matched
                            ]
                        }
                        endpoint = f"/api/v1/scan/sessions/{session['session_id']}/confirm"
                        first = client.post(endpoint, headers=headers, json=payload).json()["data"]
                        retry = client.post(endpoint, headers=headers, json=payload).json()["data"]
                        assert first["added_count"] == 2 and retry["added_count"] == 0
                        assert first["quantities"] == retry["quantities"]
                        result["confirmation"] = first
                        result["retry"] = retry
                    report["cases"].append(result)
            (args.output / "report.json").write_text(
                json.dumps(report, indent=2, ensure_ascii=False)
            )
            print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
