"""姿态特征提取器（Phase 7）。

使用 YOLOv8n-pose ONNX（17 个 COCO 关键点）通过 onnxruntime 推理，**无需 torch**。

输出 34 维向量 = 17 关键点 × (x, y)，以可见关键点的质心为原点、最大跨度为尺度做
归一化（对平移 / 缩放不变），最后 L2 归一化。与 MockPoseExtractor 维度一致（34），
保证卡片库维度稳定。

若未检测到人体或模型缺失 -> extract 返回 None，由 scoring 层触发权重动态重分配。
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image

from .base import BaseExtractor

DEFAULT_MODEL_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "models",
    "pose",
    "yolov8n-pose.onnx",
)

# YOLOv8 COCO pose 关键点顺序
KEYPOINT_NAMES = [
    "nose", "L_eye", "R_eye", "L_ear", "R_ear",
    "L_shoulder", "R_shoulder", "L_elbow", "R_elbow", "L_wrist", "R_wrist",
    "L_hip", "R_hip", "L_knee", "R_knee", "L_ankle", "R_ankle",
]


class YoloPoseExtractor(BaseExtractor):
    dim = 34

    def __init__(self, model_path: str | None = None):
        self.model_path = model_path or os.getenv(
            "CARD_MATCHER_POSE_PATH", DEFAULT_MODEL_PATH
        )
        self._session = None
        self._input_size = 640
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
            shape = self._session.get_inputs()[0].shape
            if len(shape) == 4 and isinstance(shape[2], int):
                self._input_size = shape[2]
            return True
        except Exception as e:  # noqa: BLE001
            print(f"[warn] YoloPose 模型加载失败: {e}")
            return False

    def extract(self, image: Image.Image):
        if not self._ensure_loaded():
            return None
        img = image.convert("RGB")
        w, h = img.size
        resized = img.resize((self._input_size, self._input_size), Image.BILINEAR)
        blob = np.asarray(resized, dtype=np.float32) / 255.0  # HWC, 0-1
        blob = blob.transpose(2, 0, 1)[np.newaxis, ...]  # NCHW

        out = self._session.run(None, {self._session.get_inputs()[0].name: blob})[0]
        # shape: [1, 56, 8400] -> [8400, 56]  (4 bbox + 1 cls + 17*3 kp)
        pred = out[0].T
        cls = pred[:, 4]
        best = int(np.argmax(cls))
        if cls[best] < 0.3:
            return None

        kps = pred[best, 5:56].reshape(17, 3)  # x, y, conf (input 尺寸空间)
        xs = kps[:, 0] / self._input_size * w
        ys = kps[:, 1] / self._input_size * h
        confs = kps[:, 2]
        vis = confs > 0.3
        if vis.sum() < 3:
            return None

        cx = float(xs[vis].mean())
        cy = float(ys[vis].mean())
        dx = xs[vis] - cx
        dy = ys[vis] - cy
        scale = float(np.sqrt((dx ** 2 + dy ** 2).max())) + 1e-6

        nx = np.where(vis, (xs - cx) / scale, 0.0)
        ny = np.where(vis, (ys - cy) / scale, 0.0)
        vec = np.stack([nx, ny], axis=1).reshape(-1).astype(np.float64)
        norm = float(np.linalg.norm(vec))
        if norm < 1e-9:
            return None
        return vec / norm
