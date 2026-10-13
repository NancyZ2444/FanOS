"""身体 / 衣服特征提取器（OSNet-x1.0，ONNX，无需 torch）。

使用 ONNX Model Zoo / hailo 导出的 osnet_x1_0.onnx（market1501 训练，输入 256×128，
输出 512 维 L2 归一化向量），通过 onnxruntime 推理。**完全不依赖 torch / torchreid**，
规避 cp313 + x86_64 无 torch wheel 的限制（见对话记录）。

预处理（已用真实卡片实测校准）：
  - 裁剪上半身区域（躯干 / 衣服为主），与 LightweightBodyExtractor 保持一致，
    保证换模型前后 body 特征空间在「同一裁剪约定」下可比；
  - resize 到 (W, H) = (128, 256)，即模型输入 NCHW = [1, 3, 256, 128]；
  - 像素值 /255 后做 ImageNet 归一化（mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225]）；
  - 输出 512 维向量再做一次 L2 归一化，与 cosine 打分对齐。

若模型权重缺失或加载失败 -> extract 返回 None，由 scoring 层触发权重动态重分配；
工厂层会在此基础上降级为 LightweightBodyExtractor（真实颜色直方图），保证闭环不阻塞。
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image

from .base import BaseExtractor

# card-matcher/models/osnet/osnet_x1_0.onnx
DEFAULT_MODEL_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "models",
    "osnet",
    "osnet_x1_0.onnx",
)

# OSNet 标准 ImageNet 归一化参数（与 market1501 训练一致）
_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32).reshape(3, 1, 1)
_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32).reshape(3, 1, 1)

# 模型输入尺寸（H, W）；crop 时按 (W, H) = (128, 256) resize
_INPUT_H = 256
_INPUT_W = 128


class OsnetOnnxExtractor(BaseExtractor):
    dim = 512

    def __init__(self, model_path: str | None = None):
        self.model_path = model_path or os.getenv(
            "CARD_MATCHER_OSNET_ONNX_PATH", DEFAULT_MODEL_PATH
        )
        self._session = None
        self._available = os.path.isfile(self.model_path)

    # ---- 懒加载单例 ----
    def _ensure_loaded(self) -> bool:
        if self._session is not None:
            return True
        if not self._available:
            return False
        try:
            import onnxruntime as ort

            self._session = ort.InferenceSession(
                self.model_path, providers=["CPUExecutionProvider"]
            )
            return True
        except Exception as e:  # noqa: BLE001
            print(f"[warn] OsnetOnnx 模型加载失败: {e}")
            return False

    @staticmethod
    def _crop_upper_body(img: Image.Image) -> Image.Image:
        """上半身裁剪（与 LightweightBodyExtractor 一致）：居中 60% 宽，纵向 18%~72%。"""
        w, h = img.size
        x0, x1 = int(w * 0.20), int(w * 0.80)
        y0, y1 = int(h * 0.18), int(h * 0.72)
        return img.crop((x0, y0, x1, y1)).resize((_INPUT_W, _INPUT_H))

    def _preprocess(self, crop: Image.Image) -> np.ndarray:
        """256×128 RGB -> NCHW float32，/255 + ImageNet 归一化。"""
        arr = np.asarray(crop.convert("RGB"), dtype=np.float32)
        arr = arr.transpose(2, 0, 1)  # HWC -> CHW
        arr = arr / 255.0
        arr = (arr - _MEAN) / _STD
        return arr[np.newaxis, ...].astype(np.float32)  # NCHW

    def extract(self, image: Image.Image):
        if not self._ensure_loaded():
            return None
        try:
            crop = self._crop_upper_body(image)
            x = self._preprocess(crop)
            inp = self._session.get_inputs()[0].name
            out = self._session.run(None, {inp: x})[0][0]  # (512,)
            vec = np.asarray(out, dtype=np.float32)
            norm = float(np.linalg.norm(vec))
            if norm < 1e-9:
                return None
            return (vec / norm).astype(np.float32)
        except Exception as e:  # noqa: BLE001
            print(f"[warn] OsnetOnnx 推理失败: {e}")
            return None
