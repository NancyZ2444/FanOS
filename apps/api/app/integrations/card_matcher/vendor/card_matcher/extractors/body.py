"""身体 / 衣服特征提取器：OSNet（torchreid）。

真实权重需手动放置到固定路径（见 MODELS.md）：
    card-matcher/models/osnet/osnet_x1_0.pth
可用环境变量 CARD_MATCHER_OSNET_PATH 覆盖。

设计要点（与 face extractor 保持一致）：
  - torchreid 未安装 / 权重缺失 / 提取失败时，extract 返回 None，
    由 scoring 层触发权重动态重分配，MVP（mock）闭环不被阻塞。
  - 模型懒加载（首次 extract 时才 import torchreid + 构图），
    测试与 mock 路径不会拖入 torch 重依赖。
  - 输入 PIL(RGB) -> 临时 PNG -> torchreid 读取为 RGB（与 ImageNet/OSNet 训练一致）
    -> 输出 L2 归一化 512 维向量。
"""
from __future__ import annotations

import os
import tempfile
from typing import Optional

import numpy as np
from PIL import Image

from .base import BaseExtractor

# card-matcher/models/osnet/osnet_x1_0.pth
DEFAULT_MODEL_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "models",
    "osnet",
    "osnet_x1_0.pth",
)

try:
    import torchreid  # noqa: F401

    _TORCHREID_AVAILABLE = True
except Exception:  # noqa: BLE001
    _TORCHREID_AVAILABLE = False


class BodyExtractor(BaseExtractor):
    dim: int = 512

    def __init__(self, model_path: Optional[str] = None, device: str = "cpu"):
        self.model_path = model_path or os.getenv(
            "CARD_MATCHER_OSNET_PATH", DEFAULT_MODEL_PATH
        )
        self.device = device
        self._extractor = None

    # ---- 懒加载单例（避免 import torch 拖慢测试 / mock 路径） ----
    def _ensure_loaded(self) -> bool:
        if self._extractor is not None:
            return True
        if not _TORCHREID_AVAILABLE:
            return False
        if not os.path.isfile(self.model_path):
            # 权重缺失：不触发 torchreid 自带下载（其 release 链接已失效且本环境不可达）
            return False
        try:
            from torchreid.utils import FeatureExtractor

            self._extractor = FeatureExtractor(
                model_name="osnet_x1_0",
                model_path=self.model_path,
                device=self.device,
            )
            return True
        except Exception:  # noqa: BLE001
            self._extractor = None
            return False

    def extract(self, image: Image.Image) -> Optional[np.ndarray]:
        if not self._ensure_loaded():
            return None
        tmp_path = None
        try:
            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
                tmp_path = tf.name
                image.save(tf, format="PNG")
            try:
                feats = self._extractor([tmp_path])  # 形状 (1, 512)
                vec = np.asarray(feats[0], dtype=np.float32)
            finally:
                if tmp_path and os.path.exists(tmp_path):
                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
        except Exception:  # noqa: BLE001
            return None

        norm = float(np.linalg.norm(vec))
        if norm < 1e-9:
            return None
        return (vec / norm).astype(np.float32)
