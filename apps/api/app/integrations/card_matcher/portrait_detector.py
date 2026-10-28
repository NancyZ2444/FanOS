"""Local, presence-only portrait gate; no identity or biometric embeddings.

Card-shaped geometry alone also describes keyboards and screen borders. Require
high-confidence facial evidence inside each rectified crop before offering it to
the user. A weak response may request bounded image normalization, but never
counts as a person by itself. Missing models must never bypass the gate.
"""

from __future__ import annotations

import hashlib
from functools import lru_cache
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ENGINE = "yunet-portrait-presence-v2"
MODEL_SHA256 = "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"
MODEL_PATH = Path(__file__).with_name("models") / "face_detection_yunet_2023mar.onnx"
ACCEPT_SCORE = 0.88
# A proposal can select a retry orientation, but is never accepted directly.
RETRY_SCORE = 0.65


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
            self.network = cv2.FaceDetectorYN_create(_verified_model(), "", (320, 320), RETRY_SCORE)
        except (cv2.error, AttributeError) as exc:
            raise PortraitDetectorUnavailable("Portrait detection engine unavailable") from exc

    @staticmethod
    def available() -> bool:
        try:
            PortraitDetector()
            return True
        except PortraitDetectorUnavailable:
            return False

    def _score(self, bgr, content_size, transform=None, *, upright_only=False) -> float:
        """Measure faces in original crop coordinates, excluding added borders."""
        height, width = bgr.shape[:2]
        self.network.setInputSize((width, height))
        _, faces = self.network.detect(bgr)
        if faces is None:
            return 0.0
        content_width, content_height = content_size
        content = np.float32(
            [[0, 0], [content_width, 0], [content_width, content_height], [0, content_height]]
        )
        inverse = cv2.invertAffineTransform(transform) if transform is not None else None
        score = 0.0
        for face in faces:
            x, y, w, h = face[:4]
            if min(w, h) < 10 or not 0.008 <= w * h / (content_width * content_height) <= 0.85:
                continue
            if upright_only:
                # YuNet can score a sideways face highly too. Use only its
                # transient eye/mouth geometry (never stored or identified)
                # to require eyes above the mouth in the display orientation.
                eyes = face[4:8].reshape(2, 2)
                mouth = face[10:14].reshape(2, 2)
                down = mouth.mean(axis=0) - eyes.mean(axis=0)
                across = eyes[1] - eyes[0]
                if (
                    not np.isfinite(np.concatenate((eyes, mouth))).all()
                    or down[1] < h * 0.08
                    or abs(down[0]) > down[1] * 0.7
                    or abs(across[1]) > abs(across[0]) * 0.7
                ):
                    continue
            polygon = np.float32([[x, y], [x + w, y], [x + w, y + h], [x, y + h]])
            if inverse is not None:
                polygon = cv2.transform(polygon[None], inverse)[0]
            visible, _ = cv2.intersectConvexConvex(polygon, content)
            if visible / (w * h) >= 0.85:
                score = max(score, float(face[-1]))
        return score

    @staticmethod
    def _resize(bgr, size):
        scale = min(3.0, size / max(bgr.shape[:2]))
        return cv2.resize(bgr, (round(bgr.shape[1] * scale), round(bgr.shape[0] * scale)))

    def _padded_score(self, bgr, *, angle=0, padding=0.25):
        height, width = bgr.shape[:2]
        border = round(max(width, height) * padding)
        transform = cv2.getRotationMatrix2D((width / 2, height / 2), angle, 1.0)
        transform[:, 2] += border
        padded = cv2.warpAffine(
            bgr,
            transform,
            (width + 2 * border, height + 2 * border),
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=(127, 127, 127),
        )
        return self._score(padded, (width, height), transform)

    def display_rotation_quarter_turns(self, image: Image.Image) -> int | None:
        """Conservative upright-display hint, separate from the presence gate.

        Only an unambiguous, high-confidence cardinal orientation is returned.
        This neither changes detection acceptance nor identifies a person; a
        blank/uncertain crop has no hint instead of being rotated by shape.
        The return value is clockwise, matching Flutter's RotatedBox.
        """
        rgb = np.asarray(image.convert("RGB"))
        if min(rgb.shape[:2]) < 24:
            return None
        bgr = self._resize(cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR), 320)
        scores = []
        try:
            for turns in range(4):
                oriented = np.ascontiguousarray(np.rot90(bgr, turns))
                score = self._score(
                    oriented, (oriented.shape[1], oriented.shape[0]), upright_only=True
                )
                scores.append((score, turns))
        except cv2.error as exc:
            raise PortraitDetectorUnavailable("Portrait orientation inference failed") from exc
        scores.sort(reverse=True)
        best, runner_up = scores[:2]
        if best[0] < ACCEPT_SCORE or runner_up[0] >= ACCEPT_SCORE or best[0] - runner_up[0] < 0.05:
            return None
        return (-best[1]) % 4

    def contains_person(self, image: Image.Image) -> bool:
        rgb = np.asarray(image.convert("RGB"))
        if min(rgb.shape[:2]) < 24:
            return False
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        small = self._resize(bgr, 320)
        # Retain the four cardinal orientations and the original acceptance
        # confidence. Only the strongest plausible orientation gets retries;
        # blank pockets/keyboards do not pay for a full augmented search.
        best_score, best_turns = 0.0, 0
        try:
            for turns in (0, 1, 3, 2):
                oriented = np.ascontiguousarray(np.rot90(small, turns))
                score = self._score(oriented, (oriented.shape[1], oriented.shape[0]))
                if score >= ACCEPT_SCORE:
                    return True
                if score > best_score:
                    best_score, best_turns = score, turns
            if best_score < RETRY_SCORE:
                return False

            # Different sampling and a neutral border recover tightly cropped
            # faces without reducing confidence or increasing the allowed area.
            larger = np.ascontiguousarray(np.rot90(self._resize(bgr, 480), best_turns))
            if self._padded_score(larger, padding=0.125) >= ACCEPT_SCORE:
                return True
            oriented = np.ascontiguousarray(np.rot90(small, best_turns))
            gray = cv2.cvtColor(cv2.cvtColor(oriented, cv2.COLOR_BGR2GRAY), cv2.COLOR_GRAY2BGR)
            if self._padded_score(gray, padding=0.125) >= ACCEPT_SCORE:
                return True

            # Sleeve glare reduces local contrast and printed portraits often
            # tilt independently of the card edges. Normalize luminance and
            # test a bounded +/-30 degree head tilt.
            lab = cv2.cvtColor(oriented, cv2.COLOR_BGR2LAB)
            lab[:, :, 0] = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(lab[:, :, 0])
            normalized = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)
            for angle in (0, -30, 30):
                if self._padded_score(normalized, angle=angle) >= ACCEPT_SCORE:
                    return True

            # Thin, bright sleeve patterns survive contrast enhancement. A
            # smaller median-filtered view suppresses these high-frequency
            # outlines while retaining the broad face structure. This is the
            # final retry tier: twelve model calls maximum, four for no face.
            smooth = np.ascontiguousarray(np.rot90(self._resize(bgr, 192), best_turns))
            smooth = cv2.medianBlur(smooth, 7)
            for angle in (0, -30, 30):
                if self._padded_score(smooth, angle=angle) >= ACCEPT_SCORE:
                    return True
        except cv2.error as exc:
            raise PortraitDetectorUnavailable("Portrait detection inference failed") from exc
        return False
