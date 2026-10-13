"""Mock 提取器：用于 MVP 闭环 / 单元测试 / 模型不可用时的兜底。

设计要点：以图片字节的 sha256 作随机种子，生成「确定性」向量。
相同图片 -> 相同向量 -> 余弦相似度≈1.0；不同图片 -> 不同向量 -> 低相似度。
因此即使没有真实模型，闭环也能返回「看起来真实」的匹配结果。
"""
from __future__ import annotations

import hashlib
import io

import numpy as np
from PIL import Image

from .base import BaseExtractor


def _deterministic_vector(image: Image.Image, dim: int) -> np.ndarray:
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    digest = hashlib.sha256(buf.getvalue()).digest()
    seed = int.from_bytes(digest[:8], "big")
    rng = np.random.default_rng(seed)
    vec = rng.standard_normal(dim).astype(np.float32)
    norm = float(np.linalg.norm(vec))
    if norm > 0:
        vec = vec / norm
    return vec


class MockFaceExtractor(BaseExtractor):
    dim = 512

    def extract(self, image: Image.Image) -> np.ndarray:
        return _deterministic_vector(image, self.dim)


class MockBodyExtractor(BaseExtractor):
    dim = 512

    def extract(self, image: Image.Image) -> np.ndarray:
        return _deterministic_vector(image, self.dim)


class MockPoseExtractor(BaseExtractor):
    dim = 34  # 17 个关键点 * (x, y)

    def extract(self, image: Image.Image) -> np.ndarray:
        return _deterministic_vector(image, self.dim)


class MockExpressionExtractor(BaseExtractor):
    dim = 8  # FER+ 8 类情绪概率（与真实 EmotionFerPlusExtractor 维度一致）

    def extract(self, image: Image.Image) -> np.ndarray:
        return _deterministic_vector(image, self.dim)
