"""提取器工厂：按运行模式装配 extractor 组合。

默认全部使用 mock，保证离线 / MVP 可跑通闭环，不阻塞开发。环境变量开关：

  - CARD_MATCHER_FACE=real        -> face 用真实 InsightFace/ArcFace (buffalo_l)
  - CARD_MATCHER_BODY=real        -> body 用真实 OSNet-x1.0 ONNX（onnxruntime，无需 torch）；
                                    模型缺失/加载失败时自动降级为 LightweightBodyExtractor
                                    （真实颜色直方图特征）
  - CARD_MATCHER_BODY=lightweight -> body 用零依赖真实外观描述子
  - CARD_MATCHER_EXPRESSION=real  -> expr 用真实 emotion-ferplus ONNX（onnxruntime，无需 torch）
  - CARD_MATCHER_POSE=real        -> pose 用真实 YOLOv8n-pose ONNX（onnxruntime，无需 torch）

其余特征在对应阶段接入前仍用 mock。
「接入真实模型」对调用方完全透明：main / seed / scoring 层只依赖 BaseExtractor 接口。
"""
from __future__ import annotations

import os
from typing import Dict, Optional


def build_extractors(
    face_real: Optional[bool] = None,
    body_mode: Optional[str] = None,
    expression_real: Optional[bool] = None,
    pose_real: Optional[bool] = None,
) -> Dict[str, object]:
    from .mock import (
        MockBodyExtractor,
        MockExpressionExtractor,
        MockFaceExtractor,
        MockPoseExtractor,
    )

    if face_real is None:
        face_real = os.getenv("CARD_MATCHER_FACE", "mock").lower() == "real"
    if body_mode is None:
        body_mode = os.getenv("CARD_MATCHER_BODY", "mock").lower()
    if expression_real is None:
        expression_real = os.getenv("CARD_MATCHER_EXPRESSION", "mock").lower() == "real"
    if pose_real is None:
        pose_real = os.getenv("CARD_MATCHER_POSE", "mock").lower() == "real"

    face = MockFaceExtractor()
    if face_real:
        from .face import FaceExtractor

        face = FaceExtractor()

    body = MockBodyExtractor()
    if body_mode == "real":
        from .body_onnx import OsnetOnnxExtractor

        real_body = OsnetOnnxExtractor()
        if real_body._ensure_loaded():
            body = real_body
        else:
            print(
                "[warn] CARD_MATCHER_BODY=real 但 osnet_x1_0.onnx 不可用，"
                "body 降级为 LightweightBodyExtractor（真实颜色直方图特征）"
            )
            from .body_fallback import LightweightBodyExtractor

            body = LightweightBodyExtractor()
    elif body_mode == "lightweight":
        from .body_fallback import LightweightBodyExtractor

        body = LightweightBodyExtractor()

    expression = MockExpressionExtractor()
    if expression_real:
        from .expression import EmotionFerPlusExtractor

        # 若人脸检测器（真实 FaceExtractor）已就位，则把检测框用于表情裁剪，
        # 显著提升 FER+ 的区分度；否则回退到中心裁剪。
        detector = face if hasattr(face, "crop_largest_face") else None
        real_expr = EmotionFerPlusExtractor(face_detector=detector)
        if real_expr._ensure_loaded():
            expression = real_expr
        else:
            print(
                "[warn] CARD_MATCHER_EXPRESSION=real 但 emotion-ferplus 权重不可用，"
                "expression 降级为 MockExpressionExtractor"
            )

    pose = MockPoseExtractor()
    if pose_real:
        from .pose import YoloPoseExtractor

        real_pose = YoloPoseExtractor()
        if real_pose._ensure_loaded():
            pose = real_pose
        else:
            print(
                "[warn] CARD_MATCHER_POSE=real 但 yolov8n-pose 权重不可用，"
                "pose 降级为 MockPoseExtractor"
            )

    return {
        "face": face,
        "body": body,
        "pose": pose,
        "expression": expression,
    }
