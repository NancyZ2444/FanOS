"""特征提取器抽象接口。

所有 extractor（mock 或真实模型）都实现同一接口，调用方无需关心后端。
未来新增 InsightFace / OSNet / MediaPipe / HSEmotion 时只需提供新的实现类。
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import List, Optional

import numpy as np
from PIL import Image


class BaseExtractor(ABC):
    #: 输出向量维度（子类覆盖）
    dim: int = 512

    @abstractmethod
    def extract(self, image: Image.Image) -> Optional[np.ndarray]:
        """输入 PIL 图片，返回归一化后的特征向量（float32）。

        若图像中未检测到该特征（例如无人脸），返回 None。
        None 会被 scoring 层视为「缺失」，触发权重动态重分配。
        """
        ...

    def extract_list(self, image: Image.Image) -> Optional[List[float]]:
        emb = self.extract(image)
        if emb is None:
            return None
        return emb.astype(float).tolist()
