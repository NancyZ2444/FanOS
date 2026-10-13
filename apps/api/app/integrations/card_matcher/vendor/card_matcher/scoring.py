"""统一打分模块：cosine 相似度 + 加权融合 + 缺失特征动态重分配。

- cosine_similarity：输入两个向量，返回 [-1, 1] 的余弦相似度。
- score_card：计算四个子分数，并按权重融合为 final_score。
  - 若某特征缺失（None），该特征不参与融合，其权重在「存在的特征」间重新分配，
    保证 final_score 始终在 0-1 之间且只由有效特征决定。
"""
from __future__ import annotations

from typing import Dict, List, Optional

import numpy as np

DEFAULT_WEIGHTS: Dict[str, float] = {
    "face": 0.52,
    "body": 0.16,
    "pose": 0.20,
    "expression": 0.12,
}

FEATURES: List[str] = ["face", "body", "pose", "expression"]

# 人脸门控：当「查询图」检测到人脸时，对候选卡施加降权规则，避免 body / expression 噪声
# 把「不同人」或「无脸卡」顶到同人之前。
#   - 候选卡无脸（face=None，缺失特征原本会被权重重分配，反而放大 body/expr 噪声）-> 降权
#   - 候选卡人脸余弦 < threshold（观测：同人跨卡 ≥0.23，异人 ≤0.06）-> 视为不同人，降权
#   - 查询图自身无脸时（如 UI 截图）不触发门控，保留缺失特征动态重分配的优雅降级。
FACE_GATE: Dict[str, object] = {
    "enabled": True,
    "threshold": 0.15,  # 人脸余弦低于该值即判为「非同一人」
    "penalty": 0.25,    # 命中门控时 final_score 乘以该系数
}

# 同人召回增强（任务 B）：在「人脸门控」基础上，用衣服/姿态等跨模态信号把「跨卡同人」
# 从误伤中救回，并对确认同人的卡片小幅提权，提升召回而不损伤精度。
#   - gate_body_threshold：候选卡 body(OSNet) 余弦 ≥ 该值即视为「同人」，豁免人脸门控惩罚
#     （解决：同人但人脸角度/光照差导致 ArcFace 偏低被误伤的问题）。
#   - boost_face_threshold：人脸余弦 ≥ 该值（中高相似）即确认同人，提权。
#   - boost_body_threshold：人脸过门控(≥threshold)且 body ≥ 该值联合确认同人，提权。
#   - boost_factor：提权系数，最终封顶 1.0。
RECALL: Dict[str, object] = {
    "enabled": True,
    "gate_body_threshold": 0.55,
    "gate_face_low": 0.05,  # 人脸余弦低于此值视为「明显非同人」，即使衣服相似也保持门控惩罚
    "boost_face_threshold": 0.30,
    "boost_body_threshold": 0.50,
    "boost_factor": 1.18,
}


def cosine_similarity(a, b) -> float:
    # 用 float64 计算以保证数值稳定（embedding 匹配场景下精度很重要）
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    na = float(np.linalg.norm(a))
    nb = float(np.linalg.norm(b))
    if na < 1e-9 or nb < 1e-9:
        return 0.0
    sim = float(np.dot(a, b) / (na * nb))
    # 钳制到 [-1, 1]，并把浮点噪声导致的"近边界"值吸附到精确边界：
    # 完全相同向量应返回恰好 1.0，完全相反应返回恰好 -1.0（相似度系统的契约）。
    if sim > 1.0:
        sim = 1.0
    elif sim < -1.0:
        sim = -1.0
    elif sim > 1.0 - 1e-7:
        sim = 1.0
    elif sim < -1.0 + 1e-7:
        sim = -1.0
    return sim


def _clamp01(x: float) -> float:
    return max(0.0, min(1.0, x))


def score_card(
    query_emb: Dict[str, Optional[List[float]]],
    card_emb: Dict[str, Optional[List[float]]],
    weights: Optional[Dict[str, float]] = None,
    face_gate: Optional[Dict[str, object]] = None,
    recall: Optional[Dict[str, object]] = None,
) -> Dict[str, object]:
    """对单张卡片打分。

    返回 {"scores": {feature: sim|None}, "final_score": float}
    scores 中缺失特征为 None；final_score 仅由存在的特征加权得到。
    所有分数统一钳制到 [0, 1]（负余弦相似度视为 0 相似度）。

    face_gate（默认 FACE_GATE）：当查询图检测到人脸时，候选卡「无脸 / 人脸余弦过低」
    会被乘以 penalty 系数降权，避免 body / expression 噪声把不同人顶到同人之前。

    recall（默认 RECALL，任务 B）：在 face_gate 之上做同人召回增强——
    衣服(OSNet)强匹配时豁免人脸门控误伤；人脸/人脸+衣服联合确认同人时小幅提权。
    """
    weights = weights or DEFAULT_WEIGHTS
    gate = face_gate or FACE_GATE
    rcfg = recall if recall is not None else RECALL
    scores: Dict[str, Optional[float]] = {}
    acc = 0.0
    total_w = 0.0
    for feat in FEATURES:
        q = query_emb.get(feat)
        c = card_emb.get(feat)
        if q is None or c is None:
            scores[feat] = None
            continue
        sim = _clamp01(cosine_similarity(q, c))
        scores[feat] = sim
        w = weights.get(feat, 0.0)
        acc += w * sim
        total_w += w
    final = _clamp01(acc / total_w) if total_w > 0 else 0.0

    # 人脸门控：查询有人脸时，对无脸 / 低人脸相似度的候选卡降权
    penalized = False
    if gate.get("enabled", False):
        q_face = query_emb.get("face")
        if q_face is not None:
            c_face = scores.get("face")
            threshold = float(gate.get("threshold", 0.15))  # type: ignore[arg-type]
            penalty = float(gate.get("penalty", 0.25))  # type: ignore[arg-type]
            if c_face is None or c_face < threshold:
                final *= penalty
                penalized = True

    # 同人召回增强（任务 B）
    if rcfg.get("enabled", False):
        c_face = scores.get("face")
        body_s = scores.get("body")
        face_th = float(gate.get("threshold", 0.15))  # type: ignore[arg-type]
        penalty = float(gate.get("penalty", 0.25))  # type: ignore[arg-type]
        gate_body = float(rcfg.get("gate_body_threshold", 0.55))  # type: ignore[arg-type]
        face_low = float(rcfg.get("gate_face_low", 0.05))  # type: ignore[arg-type]
        # 豁免（精准版）：仅当人脸处于「临界区间」(face_low <= c_face < 门控阈值)
        # 且衣服(OSNet)强匹配时才撤销门控惩罚——即「同人但脸角度/光照差」。
        # 明显非同人(c_face < face_low)即使撞衫也保持惩罚，护住精度。
        if (
            penalized
            and c_face is not None
            and face_low <= c_face < face_th
            and body_s is not None
            and body_s >= gate_body
        ):
            final = min(1.0, final / penalty)
            penalized = False
        # 提权：人脸中高相似，或「人脸过门控 + 衣服高相似」联合确认同人
        boost_face = float(rcfg.get("boost_face_threshold", 0.35))  # type: ignore[arg-type]
        boost_body = float(rcfg.get("boost_body_threshold", 0.50))  # type: ignore[arg-type]
        boost_factor = float(rcfg.get("boost_factor", 1.10))  # type: ignore[arg-type]
        is_same = (c_face is not None and c_face >= boost_face) or (
            c_face is not None
            and c_face >= face_th
            and body_s is not None
            and body_s >= boost_body
        )
        if is_same and not penalized:
            final = min(1.0, final * boost_factor)

    return {"scores": scores, "final_score": final}
