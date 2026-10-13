"""表情特征提取器（Phase 7）。

使用 ONNX Model Zoo 的 emotion-ferplus 模型（**FER+ 8 类情绪**：Neutral/Happy/
Surprise/Sad/Angry/Disgust/Fear/Contempt），通过 onnxruntime 推理，**无需 torch**，
规避 cp313 + x86_64 无 torch wheel 的限制。

输入质量决定区分度：FER+ 只有在喂入「紧凑人脸裁剪」时才能区分表情。因此本提取器
支持接入一个人脸检测器（FaceExtractor.crop_largest_face）——当提供时优先用检测框
裁剪人脸再送模型；未提供（或检测不到人脸）时回退到「中心 80% 区域」作为人脸代理。

输出 8 维 softmax 概率向量（L2 归一化）作为 expression_embedding。

若模型权重缺失或加载失败 -> extract 返回 None，由 scoring 层触发权重动态重分配。
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image

from .base import BaseExtractor

DEFAULT_MODEL_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "models",
    "expression",
    "emotion-ferplus-12.onnx",
)

# FER+ 8 类情绪（emotion-ferplus-12.onnx 输出为 8 维）
EMOTIONS = [
    "Neutral", "Happy", "Surprise", "Sad",
    "Angry", "Disgust", "Fear", "Contempt",
]


class EmotionFerPlusExtractor(BaseExtractor):
    dim = 8

    def __init__(self, model_path: str | None = None, face_detector=None):
        self.model_path = model_path or os.getenv(
            "CARD_MATCHER_EMOTION_PATH", DEFAULT_MODEL_PATH
        )
        self.face_detector = face_detector
        self._session = None
        self._available = os.path.isfile(self.model_path)

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
            print(f"[warn] EmotionFerPlus 模型加载失败: {e}")
            return False

    @staticmethod
    def _center_crop_pil(img: Image.Image) -> Image.Image:
        """中心 80% 区域作为人脸代理（无人脸检测器时的回退）。"""
        w, h = img.size
        cw, ch = int(w * 0.8), int(h * 0.8)
        left, top = (w - cw) // 2, (h - ch) // 2
        return img.crop((left, top, left + cw, top + ch))

    @staticmethod
    def _preprocess(face_img: Image.Image) -> np.ndarray:
        """64x64 灰度 + (x-127.5) 零均值（emotion-ferplus 预处理，不要额外缩放，
        否则输入幅度过小会让输出退化成常数）。返回 NCHW。"""
        gray = face_img.convert("L").resize((64, 64), Image.BILINEAR)
        arr = np.asarray(gray, dtype=np.float32)
        arr = arr - 127.5
        return arr[np.newaxis, np.newaxis, :, :]  # NCHW

    def extract(self, image: Image.Image):
        if not self._ensure_loaded():
            return None
        # 优先用检测器裁出紧凑人脸；失败/未配置则回退中心裁剪
        face_img = None
        if self.face_detector is not None and hasattr(
            self.face_detector, "crop_largest_face"
        ):
            try:
                face_img = self.face_detector.crop_largest_face(image)
            except Exception:  # noqa: BLE001
                face_img = None
        if face_img is None:
            face_img = self._center_crop_pil(image)
        x = self._preprocess(face_img)
        inp = self._session.get_inputs()[0].name
        logits = self._session.run(None, {inp: x})[0][0]
        e = np.exp(logits - np.max(logits))
        probs = e / e.sum()
        probs = probs.astype(np.float64)
        norm = float(np.linalg.norm(probs))
        if norm < 1e-9:
            return None
        return probs / norm
