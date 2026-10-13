"""FastAPI 应用入口：POST /api/cards/match。

第二阶段使用 mock extractor 跑通完整闭环，接口/数据结构已按真实模型可替换设计。
"""
from __future__ import annotations

import io
from typing import Dict

from fastapi import FastAPI, File, HTTPException, UploadFile
from PIL import Image

from .extractors.factory import build_extractors
from .models import Candidate, Card, MatchResponse, Scores
from .repository.json_repo import JsonRepository
from . import scoring

app = FastAPI(title="人物卡片相似度匹配系统", version="0.1.0")

REPO_PATH = "data/cards.json"
repo = JsonRepository(REPO_PATH)

# 默认全部 mock；CARD_MATCHER_FACE=real 启用真实人脸，CARD_MATCHER_BODY=real 启用真实身体
EXTRACTORS: Dict[str, object] = build_extractors()

FEATURES = scoring.FEATURES


def _load_image(upload: UploadFile) -> Image.Image:
    data = upload.file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty image")
    try:
        return Image.open(io.BytesIO(data)).convert("RGB")
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"invalid image: {exc}")


def _extract_all(image: Image.Image) -> Dict[str, object]:
    return {name: ex.extract(image) for name, ex in EXTRACTORS.items()}


@app.get("/health")
def health():
    return {"status": "ok", "cards": repo.count()}


@app.post("/api/cards/match", response_model=MatchResponse)
def match(image: UploadFile = File(...)):
    img = _load_image(image)
    query = _extract_all(img)

    ranked = []
    for card in repo.list():
        card_emb = {
            "face": card.face_embedding,
            "body": card.body_embedding,
            "pose": card.pose_embedding,
            "expression": card.expression_embedding,
        }
        result = scoring.score_card(query, card_emb)
        ranked.append((card.card_id, result["final_score"], result["scores"]))

    ranked.sort(key=lambda x: x[1], reverse=True)

    if not ranked:
        return MatchResponse(
            best_match_card_id=None,
            final_score=0.0,
            scores=Scores(),
            candidates=[],
        )

    best_id, best_final, best_scores = ranked[0]
    resp_scores = Scores(
        **{f: (best_scores[f] if best_scores[f] is not None else 0.0) for f in FEATURES}
    )
    candidates = [
        Candidate(
            card_id=cid,
            final_score=float(sc),
            scores=Scores(
                **{f: (s[f] if s[f] is not None else 0.0) for f in FEATURES}
            ),
        )
        for cid, sc, s in ranked[1:]
    ]
    return MatchResponse(
        best_match_card_id=best_id,
        final_score=float(best_final),
        scores=resp_scores,
        candidates=candidates,
    )
