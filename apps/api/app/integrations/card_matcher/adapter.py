from __future__ import annotations

import io
import json
from dataclasses import dataclass
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageOps

from app.core.config import get_settings
from app.integrations.card_matcher.portrait_detector import ENGINE as PORTRAIT_ENGINE
from app.integrations.card_matcher.portrait_detector import PortraitDetector
from app.integrations.card_matcher.sleeve_detector import detect_sleeve_quadrilaterals
from app.integrations.card_matcher.visual import ENGINE, features, similarity


@dataclass(frozen=True)
class DetectedRegion:
    x: float
    y: float
    width: float
    height: float
    crop: Image.Image
    # Ordered corners for editable admin cropping; public scan payload stays unchanged.
    corners: list[dict[str, float]] | None = None

    def payload(self) -> dict[str, float]:
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height}


class CardMatcherAdapter:
    """One index snapshot per scan; never return fabricated development matches."""

    def __init__(self) -> None:
        self.settings = get_settings()
        self.index_error = False
        try:
            self.records = json.loads(self.settings.card_matcher_index_path.read_text())
            if not isinstance(self.records, list):
                raise ValueError("Expected an index array")
        except FileNotFoundError:
            self.records = []
        except (OSError, ValueError):
            self.records = []
            self.index_error = True

    def indexed(self, known_cards: dict[str, str | None] | None = None) -> list[dict]:
        return [
            row
            for row in self.records
            if isinstance(row, dict)
            and isinstance(row.get("visual"), dict)
            and row["visual"].get("engine") == ENGINE
            and isinstance(row["visual"].get("descriptors"), list)
            and len(row["visual"].get("descriptors", [])) >= 8
            and (
                known_cards is None
                or (
                    row.get("card_id") in known_cards
                    and row.get("image_url") == known_cards[row["card_id"]]
                )
            )
        ]

    def readiness(self, known_cards: dict[str, str | None] | None = None) -> dict[str, Any]:
        count = len(self.indexed(known_cards))
        missing = [] if count else ["official_card_index"]
        detector_available = PortraitDetector.available()
        if not detector_available:
            missing.append("portrait_detector")
        if self.index_error:
            missing.append("invalid_card_index")
        return {
            "available": bool(count) and detector_available,
            "detector_available": detector_available,
            "detector_engine": PORTRAIT_ENGINE,
            "person_required": True,
            "production_ready": False,
            "engine": ENGINE,
            "indexed_card_count": count,
            "legacy_index_count": sum(
                not isinstance(r.get("visual"), dict) for r in self.records if isinstance(r, dict)
            ),
            "extractor_modes": {"artwork": "real"},
            "missing_requirements": missing,
            "message": "人物检测服务暂未就绪，请检查模型文件"
            if not detector_available
            else "可扫描已收录的人物小卡"
            if count
            else "图鉴尚未建立可用卡图索引，请先上传卡片正面并生成索引",
        }

    @staticmethod
    def index_entry(card_id: str, image: Image.Image, image_url: str) -> dict:
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")
        # Admin indexing accepts non-portrait artwork/back sides too. The public
        # scanning flow, unlike indexing/crop tooling, always requires a person.
        regions = CardMatcherAdapter.detect(buffer.getvalue(), require_person=False)
        if len(regions) != 1:
            raise ValueError("建库照片需仅包含一张小卡，请先裁剪正面图片")
        visual = features(regions[0].crop)
        if len(visual["descriptors"]) < 8:
            raise ValueError("卡图细节不足，请上传清晰完整的正面照片")
        return {
            "card_id": card_id,
            "image_url": image_url,
            "index_crop_region": regions[0].payload(),
            "visual": visual,
        }

    @staticmethod
    def detect(content: bytes, *, require_person: bool = True) -> list[DetectedRegion]:
        settings = get_settings()
        with Image.open(io.BytesIO(content)) as source:
            if source.width * source.height > settings.scan_max_pixels:
                raise ValueError("Image dimensions too large")
            image = ImageOps.exif_transpose(source).convert("RGB")
        image.thumbnail((2400, 2400))
        portrait = PortraitDetector() if require_person else None
        array = np.asarray(image)
        # Transparent sleeve seams connect neighbouring Canny outlines. A
        # repeated layout supported by long boundaries takes precedence over
        # the enclosing page; the ordinary detector remains the fallback for
        # loose/single/perspective cards. No prescribed grid or count is used.
        sleeve_points = detect_sleeve_quadrilaterals(array)
        gray = cv2.cvtColor(array, cv2.COLOR_RGB2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        contours = []
        for low, high in ((45, 130), (8, 28)):
            edges = cv2.Canny(blurred, low, high)
            edges = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
            found, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
            contours.extend(found)
        candidates = []
        for contour in contours:
            hull = cv2.convexHull(contour)
            if (
                cv2.contourArea(hull) == 0
                or cv2.contourArea(contour) / cv2.contourArea(hull) < 0.65
            ):
                continue
            polygon = cv2.approxPolyDP(hull, 0.025 * cv2.arcLength(hull, True), True)
            area = abs(cv2.contourArea(polygon))
            if len(polygon) != 4 or not cv2.isContourConvex(polygon):
                continue
            if not 0.005 <= area / (image.width * image.height) <= 0.99:
                continue
            points = polygon.reshape(4, 2).astype(np.float32)
            points = np.roll(points, -np.argmin(points.sum(axis=1)), axis=0)
            a, b = points[1] - points[0], points[2] - points[1]
            if a[0] * b[1] - a[1] * b[0] < 0:
                points = points[[0, 3, 2, 1]]
            w = max(np.linalg.norm(points[1] - points[0]), np.linalg.norm(points[2] - points[3]))
            h = max(np.linalg.norm(points[3] - points[0]), np.linalg.norm(points[2] - points[1]))
            if not 0.45 <= min(w, h) / max(w, h) <= 0.88:
                continue
            if min(w, h) < 40:
                continue
            candidates.append((area, points, int(w), int(h)))
        if sleeve_points:
            candidates = [
                (
                    abs(cv2.contourArea(points)),
                    points,
                    int(
                        max(
                            np.linalg.norm(points[1] - points[0]),
                            np.linalg.norm(points[2] - points[3]),
                        )
                    ),
                    int(
                        max(
                            np.linalg.norm(points[3] - points[0]),
                            np.linalg.norm(points[2] - points[1]),
                        )
                    ),
                )
                for points in sleeve_points
            ]

        def rectify(points, w, h):
            target = np.float32([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]])
            return Image.fromarray(
                cv2.warpPerspective(array, cv2.getPerspectiveTransform(points, target), (w, h))
            )

        # Filter before enclosure suppression as well as NMS: keyboard keys or
        # artwork rectangles must not cause a valid outer card to be discarded.
        had_candidates = bool(candidates)
        if portrait is not None:
            candidates = [
                candidate
                for candidate in candidates
                if portrait.contains_person(rectify(candidate[1], candidate[2], candidate[3]))
            ]
        # An album/page/table outline can have a photocard aspect ratio too.
        # Discard enclosing frames before NMS if they contain multiple distinct
        # card-sized quadrilaterals; otherwise largest-first NMS eats every card.
        card_candidates = []
        for candidate in candidates:
            area, points, _, _ = candidate
            children = []
            for child in sorted(candidates, key=lambda item: -item[0]):
                child_area, child_points, _, _ = child
                if not 0.025 <= child_area / area <= 0.72:
                    continue
                intersection, _ = cv2.intersectConvexConvex(points, child_points)
                if intersection / child_area < 0.9:
                    continue
                if any(
                    cv2.intersectConvexConvex(child_points, other[1])[0] / min(child_area, other[0])
                    > 0.2
                    for other in children
                ):
                    continue
                children.append(child)
            if len(children) >= 2 and sum(child[0] for child in children) / area >= 0.2:
                continue
            card_candidates.append(candidate)
        kept = []
        for _, points, w, h in sorted(card_candidates, key=lambda item: -item[0]):
            x, y, bw, bh = cv2.boundingRect(points)
            if any(
                max(0, min(x + bw, ox + ow) - max(x, ox))
                * max(0, min(y + bh, oy + oh) - max(y, oy))
                / (bw * bh)
                > 0.75
                for ox, oy, ow, oh, _, _ in kept
            ):
                continue
            crop = rectify(points, w, h)
            corners = [
                {
                    "x": float(px) / max(1, image.width - 1),
                    "y": float(py) / max(1, image.height - 1),
                }
                for px, py in points
            ]
            kept.append((x, y, min(bw, image.width - x), min(bh, image.height - y), crop, corners))
        if len(kept) > settings.card_detector_max_cards:
            raise OverflowError("Too many cards")
        if not kept and (portrait is None or not had_candidates):
            # Only a tight, card-shaped portrait may use the whole image. Never
            # turn rejected keyboard/screen regions back into one huge card.
            ratio = min(image.size) / max(image.size)
            if portrait is None or (0.45 <= ratio <= 0.88 and portrait.contains_person(image)):
                kept = [(0, 0, image.width, image.height, image, None)]
        return [
            DetectedRegion(
                x / image.width, y / image.height, w / image.width, h / image.height, crop, corners
            )
            for x, y, w, h, crop, corners in sorted(kept, key=lambda item: (item[1] // 50, item[0]))
        ]

    def rank(self, crop: Image.Image, known_cards: dict[str, str | None]) -> list[dict[str, Any]]:
        query = features(crop)
        ranked = []
        for row in self.indexed(known_cards):
            try:
                score, evidence = similarity(query, row["visual"])
            except (KeyError, ValueError, cv2.error):
                continue
            if score:
                ranked.append(
                    {"card_id": row["card_id"], "similarity": score, "feature_scores": evidence}
                )
        ranked.sort(key=lambda item: item["similarity"], reverse=True)
        return ranked[: self.settings.card_matcher_max_candidates]
