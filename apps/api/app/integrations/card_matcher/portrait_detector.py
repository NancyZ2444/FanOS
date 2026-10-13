"""Local, presence-only portrait gate; no identity or biometric embeddings.

Card-shaped geometry alone also describes keyboards and screen borders. Require
high-confidence facial evidence inside each rectified crop before offering it to
the user. Occluded faces/back views can be missed: callers must offer a retake,
never silently bypass this gate when the model is missing.
"""

from __future__ import annotations

import hashlib
from functools import lru_cache
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ENGINE = "yunet-portrait-presence-v1"
MODEL_SHA256 = "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"
MODEL_PATH = Path(__file__).with_name("models") / "face_detection_yunet_2023mar.onnx"


class PortraitDetectorUnavailable(RuntimeError):
    pass


@lru_cache(maxsize=1)
def _verified_model() -> str:
    try:
        if hashlib.sha256(MODEL_PATH.read_bytes()).hexdigest() != MODEL_SHA256:
            raise ValueError("Portrait model checksum mismatch")
    except (OSError, ValueError) as exc:
        raise PortraitDetectorUnavailable("Portrait detection model unavailable") from exc
    return str(MODEL_PATH)


class PortraitDetector:
    def __init__(self) -> None:
        try:
            # One mutable OpenCV network per request, not a shared singleton.
            self.network = cv2.FaceDetectorYN_create(_verified_model(), "", (320, 320), 0.88)
        except (cv2.error, AttributeError) as exc:
            raise PortraitDetectorUnavailable("Portrait detection engine unavailable") from exc

    @staticmethod
    def available() -> bool:
        try:
            PortraitDetector()
            return True
        except PortraitDetectorUnavailable:
            return False

    def contains_person(self, image: Image.Image) -> bool:
        rgb = np.asarray(image.convert("RGB"))
        if min(rgb.shape[:2]) < 24:
            return False
        # Bound CPU/memory cost and support sideways/upside-down printed cards.
        # Upscaling helps small cards without running a full-photo network for
        # every crop. No files or network requests are made during inference.
        scale = min(3.0, 320 / max(rgb.shape[:2]))
        rgb = cv2.resize(rgb, (round(rgb.shape[1] * scale), round(rgb.shape[0] * scale)))
        try:
            for turns in (0, 1, 3, 2):
                bgr = cv2.cvtColor(np.ascontiguousarray(np.rot90(rgb, turns)), cv2.COLOR_RGB2BGR)
                height, width = bgr.shape[:2]
                self.network.setInputSize((width, height))
                _, faces = self.network.detect(bgr)
                if faces is None:
                    continue
                for x, y, w, h, *_rest in faces:
                    # Reject tiny background faces and mostly out-of-frame
                    # fragments, but permit multiple people in a group card.
                    visible = max(0, min(x + w, width) - max(x, 0)) * max(
                        0, min(y + h, height) - max(y, 0)
                    )
                    if (
                        min(w, h) >= 10
                        and 0.008 <= w * h / (width * height) <= 0.85
                        and visible / (w * h) >= 0.85
                    ):
                        return True
        except cv2.error as exc:
            raise PortraitDetectorUnavailable("Portrait detection inference failed") from exc
        return False
