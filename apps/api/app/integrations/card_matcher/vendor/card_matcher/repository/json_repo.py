"""JSON 文件存储实现（MVP）。

接口仅为 add / list / get / count，未来可无缝替换为 pgvector 实现。
embedding 以 list[float] 直接序列化进 JSON。
"""
from __future__ import annotations

import json
import os
from typing import Dict, List, Optional

from ..models import Card


class JsonRepository:
    def __init__(self, path: str = "data/cards.json"):
        self.path = path
        self._cards: Dict[str, Card] = {}
        self._load()

    def _load(self) -> None:
        if os.path.exists(self.path):
            try:
                with open(self.path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                for d in data:
                    self._cards[d["card_id"]] = Card.from_dict(d)
            except (json.JSONDecodeError, OSError):
                self._cards = {}

    def _save(self) -> None:
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(
                [c.to_dict() for c in self._cards.values()],
                f,
                ensure_ascii=False,
                indent=2,
            )

    def add(self, card: Card) -> Card:
        self._cards[card.card_id] = card
        self._save()
        return card

    def list(self) -> List[Card]:
        return list(self._cards.values())

    def get(self, card_id: str) -> Optional[Card]:
        return self._cards.get(card_id)

    def count(self) -> int:
        return len(self._cards)
