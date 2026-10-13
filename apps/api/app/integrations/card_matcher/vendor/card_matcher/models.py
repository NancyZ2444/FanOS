"""数据模型：卡片实体（dataclass）+ API 响应 schema（Pydantic）。"""
from __future__ import annotations

from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from pydantic import BaseModel


@dataclass
class Card:
    """一张人物卡片在库中的存储形态。embedding 以 list[float] 持久化。"""

    card_id: str
    person_name: Optional[str] = None
    image_path: Optional[str] = None
    image_url: Optional[str] = None
    face_embedding: Optional[List[float]] = None
    body_embedding: Optional[List[float]] = None
    pose_embedding: Optional[List[float]] = None
    expression_embedding: Optional[List[float]] = None
    created_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Card":
        return cls(**d)


# ----------------------- API 响应 schema -----------------------


class Scores(BaseModel):
    face: float = 0.0
    body: float = 0.0
    pose: float = 0.0
    expression: float = 0.0


class Candidate(BaseModel):
    card_id: str
    final_score: float
    scores: Scores


class MatchResponse(BaseModel):
    best_match_card_id: Optional[str] = None
    final_score: float = 0.0
    scores: Scores = Scores()
    candidates: List[Candidate] = []
