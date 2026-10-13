"""真实人脸特征提取器：基于 InsightFace / ArcFace (buffalo_l)。

- 使用 insightface 的 FaceAnalysis 检测人脸并提取 ArcFace 512 维 embedding。
- embedding 已 L2 归一化；本类再确保一次，便于直接做 cosine 相似度。
- 未检测到人脸时返回 None（缺失语义交由 scoring 层处理）。
- 自适应 det_size：默认 (640,640) 对大图(如库内卡)效果最佳，但对小图
  (如截图 <320px) 会漏检；此时自动降级到更小的 det_size 重试。
- 依赖/模型不可用时（未安装 insightface、或 buffalo_l 模型无法下载/缺失），
  实例化会抛出清晰可执行的 RuntimeError，而不是静默兜底成错误结果。
"""
from __future__ import annotations

import os
from typing import List, Optional, Tuple

import numpy as np
from PIL import Image

from .base import BaseExtractor

# 当默认 det_size 漏检时，依次尝试的备选 det_size（从大到小）
_FALLBACK_DET_SIZES: List[Tuple[int, int]] = [
    (320, 320),
    (256, 256),
    (192, 192),
    (128, 128),
]


class FaceExtractor(BaseExtractor):
    dim = 512

    def __init__(
        self,
        model_name: str = "buffalo_l",
        det_size=(640, 640),
        ctx_id: int = -1,
        providers=("CPUExecutionProvider",),
        root: Optional[str] = None,
    ):
        try:
            from insightface.app import FaceAnalysis
        except ImportError as exc:  # pragma: no cover - 依赖缺失
            raise RuntimeError(
                "InsightFace 未安装。请执行: pip install insightface onnxruntime"
            ) from exc

        # 允许通过环境变量指定模型目录（默认 ~/.insightface），方便离线/内网环境放置模型
        root = root or os.getenv("CARD_MATCHER_INSIGHTFACE_ROOT")

        # 主检测器使用配置的 det_size（默认 640——对大图最优）
        self._det_size = det_size
        self._providers = providers
        self._model_name = model_name
        self._ctx_id = ctx_id
        self._root = root

        try:
            if root:
                self.app = FaceAnalysis(
                    name=model_name, root=root, det_size=det_size,
                    providers=providers,
                )
            else:
                self.app = FaceAnalysis(
                    name=model_name, det_size=det_size, providers=providers
                )
            self.app.prepare(ctx_id=ctx_id, det_size=det_size)
        except Exception as exc:  # 模型下载失败 / 文件缺失 / onnx 错误等
            raise RuntimeError(
                f"加载 InsightFace 模型 '{model_name}' 失败：{exc}\n"
                f"请确认模型目录已就位（默认 {os.path.expanduser('~/.insightface/models/buffalo_l/')}），"
                f"或当前环境可访问 GitHub releases 自动下载；也可设置 "
                f"CARD_MATCHER_INSIGHTFACE_ROOT 指向已解压的模型目录。"
            ) from exc

    def _detect(self, bgr: np.ndarray) -> list:
        """用主检测器检测人脸；若未检出且图片较小，自动降级 det_size 重试。

        返回 insightface face 对象列表（可能为空）。
        """
        faces = self.app.get(bgr)
        if faces:
            return faces

        # 小图漏检时，尝试更小的 det_size
        h, w = bgr.shape[:2]
        if max(h, w) < self._det_size[0]:
            for fb_ds in _FALLBACK_DET_SIZES:
                if fb_ds[0] >= max(h, w):
                    continue  # 比图片还大，跳过
                from insightface.app import FaceAnalysis
                fb_app = FaceAnalysis(
                    name=self._model_name, det_size=fb_ds,
                    providers=self._providers,
                )
                if self._root:
                    fb_app = FaceAnalysis(
                        name=self._model_name, root=self._root,
                        det_size=fb_ds, providers=self._providers,
                    )
                fb_app.prepare(ctx_id=self._ctx_id, det_size=fb_ds)
                faces = fb_app.get(bgr)
                if faces:
                    return faces
        return []

    def _pick_largest(self, faces: list):
        """取面积最大的人脸。"""
        return max(
            faces,
            key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]),
        )

    def extract(self, image: Image.Image) -> Optional[np.ndarray]:
        img = np.asarray(image)[:, :, ::-1]  # PIL RGB -> OpenCV BGR
        faces = self._detect(img)
        if not faces:
            return None
        face = self._pick_largest(faces)
        emb = np.asarray(face.embedding, dtype=np.float32)
        norm = float(np.linalg.norm(emb))
        if norm > 0:
            emb = emb / norm
        return emb

    def crop_largest_face(self, image: Image.Image) -> Optional[Image.Image]:
        """返回面积最大人脸的 PIL 裁剪图（带 15% 边距），无人脸返回 None。

        供表情 / 年龄等需要「紧凑人脸区域」的提取器复用同一份检测结果，
        避免为同一张图重复跑检测器。
        """
        img = np.asarray(image)[:, :, ::-1]  # PIL RGB -> OpenCV BGR
        faces = self._detect(img)
        if not faces:
            return None
        face = self._pick_largest(faces)
        x1, y1, x2, y2 = [int(v) for v in face.bbox]
        bw, bh = x2 - x1, y2 - y1
        pad = 0.15
        x1 = max(0, int(x1 - bw * pad))
        y1 = max(0, int(y1 - bh * pad))
        x2 = min(image.width, int(x2 + bw * pad))
        y2 = min(image.height, int(y2 + bh * pad))
        return image.crop((x1, y1, x2, y2))
