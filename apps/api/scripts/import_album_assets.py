#!/usr/bin/env python3
"""Import optional front/back album artwork into catalog storage."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from sqlalchemy import select

API_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(API_ROOT))

from app.core.database import SessionLocal, create_schema  # noqa: E402
from app.integrations.storage import get_storage  # noqa: E402
from app.models import CatalogAlbum  # noqa: E402

SUPPORTED = (".jpg", ".jpeg", ".png", ".webp")


def _side_file(folder: Path, side: str) -> Path | None:
    return next(
        (
            folder / f"{side}{extension}"
            for extension in SUPPORTED
            if (folder / f"{side}{extension}").is_file()
        ),
        None,
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Import optional album front/back images from assets/import/albums/<album-id>/"
    )
    parser.add_argument(
        "root",
        nargs="?",
        type=Path,
        default=API_ROOT.parents[1] / "assets" / "import" / "albums",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not args.root.is_dir():
        raise SystemExit(f"专辑图片目录不存在: {args.root}")

    create_schema()
    imported = 0
    with SessionLocal() as db:
        known_ids = set(db.scalars(select(CatalogAlbum.id)).all())
        for folder in sorted(path for path in args.root.iterdir() if path.is_dir()):
            if folder.name not in known_ids:
                print(f"[skip] {folder}: 数据库中不存在 Album ID {folder.name}")
                continue
            album = db.get(CatalogAlbum, folder.name)
            for side in ("front", "back"):
                path = _side_file(folder, side)
                if path is None:
                    continue
                print(f"[import] {folder.name} {side} <- {path}")
                if args.dry_run:
                    imported += 1
                    continue
                image_url = get_storage().save_bytes(
                    path.read_bytes(), path.name, f"albums/{folder.name}"
                )
                setattr(album, f"{side}_image_url", image_url)
                if side == "front":
                    album.image_url = image_url
                imported += 1
        if not args.dry_run:
            db.commit()
    print(f"完成：导入 {imported} 个专辑卡面")


if __name__ == "__main__":
    main()
