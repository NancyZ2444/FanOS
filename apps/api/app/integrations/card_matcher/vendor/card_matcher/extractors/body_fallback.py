"""轻量身体 / 衣服特征提取器（零额外依赖，真实非 mock）。

当 OSNet 权重（osnet_x1_0.pth）在本环境不可获取时，用作 Phase 6 的真实身体 / 衣服
外观描述子。完全基于 PIL + numpy，不引入 torch / opencv：

  1. 裁剪图片上半身区域（躯干 / 衣服所在）：宽度居中 60%，纵向 18%~72%；
  2. 对裁剪块做 8x8x8 三维联合颜色直方图（3 通道各量化到 8 级 -> 512 维）；
  3. L2 归一化，与 cosine 打分对齐，维度与 OSNet(512) 完全一致。

该描述子从图像内容**真实计算**（非随机 mock）：同人同衣卡片颜色分布相近 -> 相似度高；
换衣 / 不同卡片 -> 相似度低。一旦提供 osnet_x1_0.pth，工厂会自动切回 OSNet
（CARD_MATCHER_BODY=real）。
"""
from __future__ import annotations

import numpy as np
from PIL import Image

from .base import BaseExtractor


class LightweightBodyExtractor(BaseExtractor):
    dim: int = 512
    _LEVELS = 8  # 每通道量化级数 -> 8^3 = 512 维

    def extract(self, image: Image.Image) -> np.ndarray:
        rgb = image.convert("RGB")
        w, h = rgb.size
        # 上半身裁剪框：居中 60% 宽，纵向 18%~72%（躯干 / 衣服为主）
        x0, x1 = int(w * 0.20), int(w * 0.80)
        y0, y1 = int(h * 0.18), int(h * 0.72)
        crop = rgb.crop((x0, y0, x1, y1)).resize((64, 64))

        arr = np.asarray(crop, dtype=np.uint8)
        r = (arr[:, :, 0] // (256 // self._LEVELS)).astype(np.int32)
        g = (arr[:, :, 1] // (256 // self._LEVELS)).astype(np.int32)
        b = (arr[:, :, 2] // (256 // self._LEVELS)).astype(np.int32)
        idx = (r * self._LEVELS * self._LEVELS + g * self._LEVELS + b).ravel()

        hist = np.bincount(idx, minlength=self.dim).astype(np.float32)
        norm = float(np.linalg.norm(hist))
        if norm < 1e-9:
            return np.zeros(self.dim, dtype=np.float32)
        return (hist / norm).astype(np.float32)
