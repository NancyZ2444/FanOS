"""Start the isolated feedback acceptance API with a real visual test index."""

import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "api"))

import uvicorn
from PIL import Image, ImageDraw

from app.core.config import get_settings
from app.core.database import SessionLocal, create_schema
from app.integrations.card_matcher.adapter import CardMatcherAdapter
from app.main import app
from app.models import Card
from app.seed import seed_database

settings = get_settings()
assert ".test-data/run-" in settings.database_url, "Requires an isolated test database"
create_schema()
with SessionLocal() as db:
    seed_database(db)
    image = Image.new("RGB", (360, 520), "#e8e4df")
    draw = ImageDraw.Draw(image)
    randomizer = random.Random(20261020)
    for _ in range(120):
        x, y = randomizer.randrange(30, 310), randomizer.randrange(30, 465)
        size = randomizer.randrange(5, 24)
        color = tuple(randomizer.randrange(20, 200) for _ in range(3))
        draw.ellipse((x, y, x + size, y + size), fill=color, outline="black")
    draw.text((45, 480), "FEEDBACK TEST INDEX", fill="black")
    image.save(settings.local_media_root / "feedback-reference.png")
    card = db.get(Card, "card-aria-01")
    card.image_url = f"{settings.public_media_base_url}/feedback-reference.png"
    entry = CardMatcherAdapter.index_entry(card.id, image, card.image_url)
    settings.card_matcher_index_path.write_text(json.dumps([entry]))
    db.commit()

uvicorn.run(app, host="127.0.0.1", port=8011)
