"""Use the user's local Card Atelier samples ONLY in an isolated test database.

The photos are not copied into the mobile bundle or the development/production DB.
Run with DATABASE_URL and LOCAL_MEDIA_ROOT pointing under output/album-atelier-qa.*.
"""

import shutil
from pathlib import Path

from sqlalchemy import select

from app.core.config import REPO_ROOT, get_settings
from app.core.database import SessionLocal
from app.models import Card


def main():
    settings = get_settings()
    prefix = str(REPO_ROOT / "output" / "album-atelier-qa.")
    database = settings.database_url.removeprefix("sqlite:///")
    if not database.startswith(prefix) or not str(settings.local_media_root).startswith(prefix):
        raise SystemExit("Refusing to modify a non-isolated database or media directory")
    source = Path("/Users/nancy/Documents/mini program/card-atelier/assets/cards")
    target = settings.local_media_root / "album-qa"
    target.mkdir(parents=True, exist_ok=True)
    for image in source.glob("*.jpg"):
        shutil.copy2(image, target / image.name)
    with SessionLocal() as db:
        for index, card in enumerate(db.scalars(select(Card).order_by(Card.id))):
            number = index % 5 + 1
            front = f"card_{number:02d}_front.jpg"
            back = f"card_{number:02d}_back.jpg"
            card.image_url = f"{settings.public_media_base_url}/album-qa/{front}"
            card.admin_data = {
                **(card.admin_data or {}),
                "back_image_url": f"{settings.public_media_base_url}/album-qa/{back}"
                if (target / back).is_file()
                else None,
            }
        db.commit()
    print("Isolated album fixture images ready")


if __name__ == "__main__":
    main()
