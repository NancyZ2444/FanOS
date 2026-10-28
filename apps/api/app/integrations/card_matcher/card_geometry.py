"""Supplement closed card outlines at bounded scales on textured backgrounds.

Downsampling disconnects fine tabletop texture from rounded card edges. Several
edge strengths preserve faint sleeves without requiring one global threshold.
Every proposal still needs a closed, convex, nearly rectangular boundary.
"""

from __future__ import annotations

from collections.abc import Callable

import cv2
import numpy as np


def ordered_corners(points: np.ndarray) -> np.ndarray:
    points = np.roll(points, -np.argmin(points.sum(axis=1)), axis=0)
    a, b = points[1] - points[0], points[2] - points[1]
    if a[0] * b[1] - a[1] * b[0] < 0:
        points = points[[0, 3, 2, 1]]
    return points


def touches_photo_frame(points: np.ndarray, image_size: tuple[int, int]) -> bool:
    """Count photograph sides, not vertices: one corner can touch two sides."""
    width, height = image_size
    sides = (
        points[:, 0].min() < width * 0.02,
        points[:, 0].max() > width * 0.98,
        points[:, 1].min() < height * 0.02,
        points[:, 1].max() > height * 0.98,
    )
    return sum(bool(side) for side in sides) >= 2


class CardBoundaryScorer:
    """Compare alternative outlines using contrast across each proposed edge.

    A textured table has many Canny pixels close to any arbitrary line. Sampling
    on both sides of the line instead rewards a consistent image transition.
    A weak side penalizes a box cut through artwork even if its other three
    edges follow strong card borders. The score is only comparative: it is not
    a standalone card/person classifier or a reason to reject a faint card.
    """

    def __init__(self, rgb: np.ndarray):
        height, width = rgb.shape[:2]
        scale = min(1.0, 900 / max(height, width))
        size = (max(1, round(width * scale)), max(1, round(height * scale)))
        resized = cv2.resize(rgb, size)
        self.gray = cv2.GaussianBlur(cv2.cvtColor(resized, cv2.COLOR_RGB2GRAY), (3, 3), 0).astype(
            np.float32
        )
        self.scale = np.float32([size[0] / width, size[1] / height])
        self._cache: dict[bytes, tuple[tuple[float, ...], tuple[float, ...]]] = {}

    def evidence(self, points: np.ndarray) -> tuple[tuple[float, ...], tuple[float, ...]]:
        """Return per-side visible transition fractions and consistent contrast."""
        points = np.asarray(points, dtype=np.float32)
        key = points.tobytes()
        if key in self._cache:
            return self._cache[key]
        scaled = points * self.scale
        sides = np.roll(scaled, -1, axis=0) - scaled
        lengths = np.linalg.norm(sides, axis=1)
        if len(points) != 4 or float(lengths.min()) < 1:
            return (0.0,) * 4, (0.0,) * 4
        offset = min(4.0, max(1.0, float(lengths.min()) * 0.025))
        fractions = np.linspace(0.07, 0.93, 100, dtype=np.float32)[:, None]
        coverage, contrast = [], []
        for start, side, length in zip(scaled, sides, lengths, strict=True):
            samples = start + fractions * side
            normal = np.float32([-side[1], side[0]]) / length

            def sample(at):
                return cv2.remap(
                    self.gray,
                    at[:, 0].reshape(1, -1),
                    at[:, 1].reshape(1, -1),
                    cv2.INTER_LINEAR,
                    borderMode=cv2.BORDER_REPLICATE,
                )[0]

            difference = sample(samples + offset * normal) - sample(samples - offset * normal)
            coverage.append(float((np.abs(difference) > 10).mean()))
            contrast.append(abs(float(difference.mean())))
        result = tuple(coverage), tuple(contrast)
        self._cache[key] = result
        return result

    def quality(self, points: np.ndarray) -> float:
        coverage, contrast = self.evidence(points)
        weakest_side = min(1.0, min(coverage) / 0.5)
        return float(np.mean(contrast)) * weakest_side**2

    def __call__(self, points: np.ndarray) -> float:
        return self.quality(points)


def distinct_quadrilaterals(
    candidates: list[np.ndarray],
    image_size: tuple[int, int] | None = None,
    *,
    quality: Callable[[np.ndarray], float] | None = None,
) -> list[np.ndarray]:
    """Deduplicate before expensive portrait inference, preserving nested cards."""
    kept: list[tuple[float, np.ndarray]] = []

    def priority(points):
        touches_frame = False
        if image_size is not None:
            touches_frame = touches_photo_frame(points, image_size)
        # Preserve a complete inner outline when a nearly identical screenshot
        # perimeter would otherwise erase it before enclosure suppression.
        return (
            touches_frame,
            -quality(points) if quality is not None else 0,
            -cv2.contourArea(points),
        )

    for points in sorted(candidates, key=priority):
        area = cv2.contourArea(points)
        duplicate = False
        for other_area, other in kept:
            if min(area, other_area) / max(area, other_area) <= 0.9:
                continue
            intersection = cv2.intersectConvexConvex(points, other)[0]
            if intersection / max(1, area + other_area - intersection) > 0.9:
                duplicate = True
                break
        if not duplicate:
            kept.append((area, points))
    return [points for _, points in kept]


def detect_card_quadrilaterals(rgb: np.ndarray) -> list[np.ndarray]:
    height, width = rgb.shape[:2]
    candidates: list[np.ndarray] = []
    seen_sizes = set()
    for limit in (600, 1200, 1800):
        scale = min(1, limit / max(height, width))
        size = (max(1, round(width * scale)), max(1, round(height * scale)))
        if size in seen_sizes:
            continue
        seen_sizes.add(size)
        gray = cv2.cvtColor(cv2.resize(rgb, size), cv2.COLOR_RGB2GRAY)
        # Use the actual rounded dimensions when mapping back to the image.
        back_scale = np.float32([width / size[0], height / size[1]])
        for blur in (3, 9):
            blurred = cv2.GaussianBlur(gray, (blur, blur), 0)
            for low, high in ((8, 28), (20, 60), (45, 130)):
                edges = cv2.Canny(blurred, low, high)
                for closing in (3, 5):
                    joined = cv2.morphologyEx(
                        edges, cv2.MORPH_CLOSE, np.ones((closing, closing), np.uint8)
                    )
                    contours, _ = cv2.findContours(joined, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
                    for contour in contours:
                        hull = cv2.convexHull(contour)
                        area = cv2.contourArea(hull)
                        if not 0.005 <= area / (size[0] * size[1]) <= 0.99:
                            continue
                        if cv2.contourArea(contour) / area < 0.7:
                            continue
                        perimeter = cv2.arcLength(hull, True)
                        for epsilon in (0.025, 0.04):
                            polygon = cv2.approxPolyDP(hull, epsilon * perimeter, True)
                            if len(polygon) != 4 or not cv2.isContourConvex(polygon):
                                continue
                            points = ordered_corners(
                                polygon[:, 0, :].astype(np.float32) * back_scale
                            )
                            near_edge = (
                                (points[:, 0] < width * 0.008)
                                | (points[:, 0] > width * 0.992)
                                | (points[:, 1] < height * 0.008)
                                | (points[:, 1] > height * 0.992)
                            )
                            if near_edge.sum() >= 2:
                                continue
                            sides = np.roll(points, -1, axis=0) - points
                            lengths = np.linalg.norm(sides, axis=1)
                            w, h = max(lengths[0], lengths[2]), max(lengths[1], lengths[3])
                            if min(w, h) < 40 or not 0.45 <= min(w, h) / max(w, h) <= 0.88:
                                continue
                            cosine = np.abs(
                                (sides * np.roll(sides, 1, axis=0)).sum(axis=1)
                                / (lengths * np.roll(lengths, 1))
                            )
                            if cosine.max() > 0.45 or cv2.contourArea(polygon) / area < 0.82:
                                continue
                            candidates.append(points)
    return distinct_quadrilaterals(
        candidates + _large_foreground_quadrilaterals(rgb),
        (width, height),
        quality=CardBoundaryScorer(rgb),
    )


def _large_foreground_quadrilaterals(rgb: np.ndarray) -> list[np.ndarray]:
    """Recover a large isolated card's rounded silhouette from foreground masks.

    Only large, filled rectangles wholly inside the photo qualify. Smaller
    regions must use actual closed edges or the supported sleeve layout.
    """
    height, width = rgb.shape[:2]
    scale = min(1.0, 900 / max(width, height))
    size = (max(1, round(width * scale)), max(1, round(height * scale)))
    back_scale = np.float32([width / size[0], height / size[1]])
    gray = cv2.GaussianBlur(cv2.cvtColor(cv2.resize(rgb, size), cv2.COLOR_RGB2GRAY), (5, 5), 0)
    candidates = []
    for threshold in (80, 100, 120, 160):
        _, foreground = cv2.threshold(gray, threshold, 255, cv2.THRESH_BINARY)
        for kernel in (3, 7, 13):
            joined = cv2.morphologyEx(
                foreground, cv2.MORPH_CLOSE, np.ones((kernel, kernel), np.uint8)
            )
            contours, _ = cv2.findContours(joined, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            for contour in contours:
                hull = cv2.convexHull(contour)
                hull_area = cv2.contourArea(hull)
                rectangle = cv2.minAreaRect(hull)
                w, h = rectangle[1]
                area = w * h
                if area <= 0 or not 0.45 <= min(w, h) / max(w, h) <= 0.88:
                    continue
                if not 0.4 <= area / (size[0] * size[1]) <= 0.9:
                    continue
                if hull_area / area < 0.85 or cv2.contourArea(contour) / hull_area < 0.65:
                    continue
                points = ordered_corners(cv2.boxPoints(rectangle) * back_scale)
                if (
                    points[:, 0].min() < width * 0.015
                    or points[:, 0].max() > width * 0.985
                    or points[:, 1].min() < height * 0.015
                    or points[:, 1].max() > height * 0.985
                ):
                    continue
                candidates.append(points)
    return candidates
