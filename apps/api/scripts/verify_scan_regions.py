"""Verify a real scan photo on an isolated SQLite backup; never writes the source DB."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--source-db", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-count", type=int, required=True)
    parser.add_argument("--user-id", default="current-user")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="regions-", dir=args.output))
    database = run / "verification.db"
    source_uri = args.source_db.resolve().as_uri() + "?mode=ro"
    with sqlite3.connect(source_uri, uri=True) as source, sqlite3.connect(database) as target:
        source.backup(target)
    os.environ["DATABASE_URL"] = f"sqlite:///{database.resolve()}"
    os.environ["LOCAL_MEDIA_ROOT"] = str((run / "media").resolve())
    os.environ["PUBLIC_MEDIA_BASE_URL"] = "http://scan-verification.invalid/media"
    os.environ["AUTO_SEED"] = "false"
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from app.core.database import SessionLocal
    from app.integrations.card_matcher.adapter import CardMatcherAdapter
    from app.models import User
    from app.modules.scan.service import recognize

    content = args.image.read_bytes()
    regions = CardMatcherAdapter.detect(content)
    original = ImageOps.exif_transpose(Image.open(args.image)).convert("RGB")
    annotated = original.copy()
    draw = ImageDraw.Draw(annotated)
    tiles = Image.new("RGB", (3 * 220, ((len(regions) + 2) // 3) * 342), "#f7f7fa")
    tile_draw = ImageDraw.Draw(tiles)
    for index, region in enumerate(regions, 1):
        left, top = region.x * original.width, region.y * original.height
        right = left + region.width * original.width
        bottom = top + region.height * original.height
        draw.rectangle((left, top, right, bottom), outline="#ee2255", width=4)
        draw.text((left + 5, top + 5), str(index), fill="#ee2255", stroke_width=1)
        region.crop.save(run / f"crop-{index:02d}.jpg", quality=95)
        thumb = ImageOps.contain(region.crop, (208, 308))
        col, row = (index - 1) % 3, (index - 1) // 3
        tiles.paste(thumb, (col * 220 + (220 - thumb.width) // 2, row * 342 + 8))
        tile_draw.text((col * 220 + 8, row * 342 + 320), f"Card {index}", fill="#202030")
    annotated.save(run / "detected-regions.jpg", quality=95)
    tiles.save(run / "card-crops.jpg", quality=95)
    with SessionLocal() as db:
        user = db.get(User, args.user_id)
        if user is None:
            raise ValueError("Verification user is not present in the isolated backup")
        payload = recognize(db, user, content, args.image.name)
    ids = [row["detected_card_id"] for row in payload["detected_cards"]]
    report = {
        "input": str(args.image.resolve()),
        "source_database_read_only": str(args.source_db.resolve()),
        "isolated_database": str(database.resolve()),
        "expected_count": args.expected_count,
        "detector_count": len(regions),
        "api_result_count": len(ids),
        "distinct_result_ids": len(set(ids)),
        "all_crops_persisted": all(row["crop_image_path"] for row in payload["detected_cards"]),
        "regions": [region.payload() for region in regions],
        "recognition_statuses": [row["recognition_status"] for row in payload["detected_cards"]],
        "candidate_counts": [len(row["candidates"]) for row in payload["detected_cards"]],
        "matching_is_separate_from_detection": True,
        "passed": len(regions) == len(ids) == len(set(ids)) == args.expected_count,
    }
    (run / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "count": len(ids), "output": str(run)}))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
