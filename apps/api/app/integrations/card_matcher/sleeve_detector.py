"""Conservative supplemental detector for cards in transparent album sleeves.

Transparent seams often connect every ordinary Canny contour. Directional
long-line morphology removes short artwork edges first. Only a repeated,
occupied rectangular arrangement is accepted; there is no prescribed row,
column, card count, or equal division of the photograph.
"""

from __future__ import annotations

import math

import cv2
import numpy as np


def _clusters(values: list[float], tolerance: float) -> list[float]:
    groups: list[list[float]] = []
    for value in sorted(values):
        if groups and abs(value - float(np.median(groups[-1]))) <= tolerance:
            groups[-1].append(value)
        else:
            groups.append([value])
    return [float(np.median(group)) for group in groups]


def _deskew(gray: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Correct only a small common camera tilt, not arbitrary perspective."""
    height, width = gray.shape
    found = cv2.createLineSegmentDetector(0).detect(gray)[0]
    angles, weights = [], []
    if found is not None:
        for x1, y1, x2, y2 in found[:, 0]:
            length = float(np.hypot(x2 - x1, y2 - y1))
            angle = float(np.degrees(np.arctan2(y2 - y1, x2 - x1)))
            angle = (angle + 90) % 180 - 90
            if length >= min(width, height) * 0.09 and abs(angle) <= 8:
                angles.append(angle)
                weights.append(length)
    angle = 0.0
    if angles:
        order = np.argsort(angles)
        cumulative = np.cumsum(np.asarray(weights)[order])
        angle = float(np.asarray(angles)[order][np.searchsorted(cumulative, cumulative[-1] / 2)])
    transform = cv2.getRotationMatrix2D((width / 2, height / 2), angle, 1)
    return (
        cv2.warpAffine(gray, transform, (width, height), borderMode=cv2.BORDER_REPLICATE),
        cv2.invertAffineTransform(transform),
    )


def detect_sleeve_quadrilaterals(rgb: np.ndarray) -> list[np.ndarray]:
    """Return TL/TR/BR/BL corners for an evidence-supported portrait-card grid.

    This intentionally returns nothing for single cards, missing rectangular
    evidence, very oblique pages, or ambiguous arrangements. The caller should
    retain its general contour/perspective detector and normal unknown fallback.
    """
    if rgb.ndim != 3 or rgb.shape[2] != 3:
        return []
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    gray, inverse = _deskew(gray)
    height, width = gray.shape
    short = min(width, height)
    if short < 160:
        return []
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    gx = np.abs(cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3))
    gy = np.abs(cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3))
    gap = max(3, int(short * 0.012))
    join = max(3, int(short * 0.014))
    candidates: list[tuple[int, int, int, int]] = []
    for threshold in (25, 35, 45):
        for fraction in (0.047, 0.066, 0.094):
            length = max(9, int(short * fraction))
            vertical = np.uint8(gx > threshold) * 255
            horizontal = np.uint8(gy > threshold) * 255
            vertical = cv2.morphologyEx(vertical, cv2.MORPH_CLOSE, np.ones((gap, 1), np.uint8))
            horizontal = cv2.morphologyEx(horizontal, cv2.MORPH_CLOSE, np.ones((1, gap), np.uint8))
            vertical = cv2.morphologyEx(vertical, cv2.MORPH_OPEN, np.ones((length, 1), np.uint8))
            horizontal = cv2.morphologyEx(
                horizontal, cv2.MORPH_OPEN, np.ones((1, length), np.uint8)
            )
            edges = cv2.morphologyEx(
                vertical | horizontal, cv2.MORPH_CLOSE, np.ones((join, join), np.uint8)
            )
            contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
            for contour in contours:
                x, y, w, h = cv2.boundingRect(contour)
                if not (0.48 <= w / h <= 0.82 and 0.006 <= w * h / (width * height) <= 0.24):
                    continue
                if min(w, h) < short * 0.05 or cv2.contourArea(contour) / (w * h) < 0.60:
                    continue
                if x < 2 or y < 2 or x + w > width - 2 or y + h > height - 2:
                    continue
                if (
                    float(gray[y + h // 10 : y + h - h // 10, x + w // 10 : x + w - w // 10].std())
                    < 18
                ):
                    # An empty transparent pocket can have perfect seam edges.
                    continue
                box = (x, y, w, h)
                if not any(
                    sum(abs(a - b) for a, b in zip(box, other, strict=True)) < short * 0.035
                    for other in candidates
                ):
                    candidates.append(box)
    if len(candidates) < 4:
        return []

    # Modal *observed* dimensions reject cropped edge cards, faces and whole pages.
    def neighbours(box: tuple[int, int, int, int]) -> list[tuple[int, int, int, int]]:
        return [
            other
            for other in candidates
            if abs(other[2] / box[2] - 1) <= 0.22 and abs(other[3] / box[3] - 1) <= 0.22
        ]

    group = max((neighbours(box) for box in candidates), key=len)
    median_w, median_h = np.median([box[2:] for box in group], axis=0)
    columns = _clusters([x + w / 2 for x, y, w, h in group], median_w * 0.45)
    rows = _clusters([y + h / 2 for x, y, w, h in group], median_h * 0.35)
    if len(columns) < 2 or len(rows) < 2 or len(columns) * len(rows) > 30:
        return []
    # Similar neighbour pitch is necessary; unrelated rectangles are not a grid.
    for centers, size in ((columns, median_w), (rows, median_h)):
        spacing = np.diff(centers)
        if np.any(spacing < size * 0.85) or np.any(spacing > size * 1.7):
            return []
        if spacing.max() / spacing.min() > 1.3:
            return []
    occupied: dict[tuple[int, int], tuple[int, int, int, int]] = {}
    for box in group:
        x, y, w, h = box
        row = int(np.argmin(np.abs(np.asarray(rows) - (y + h / 2))))
        column = int(np.argmin(np.abs(np.asarray(columns) - (x + w / 2))))
        key = (row, column)
        # Prefer a complete common-sized region over a smaller interior contour.
        error = abs(w / median_w - 1) + abs(h / median_h - 1)
        other = occupied.get(key)
        if other is None or error < abs(other[2] / median_w - 1) + abs(other[3] / median_h - 1):
            occupied[key] = box
    if len(occupied) < 4 or len(occupied) / (len(rows) * len(columns)) < 0.65:
        return []
    observed = len(occupied)
    maximum_filled = math.ceil(observed * 0.35)
    # A small missing contour may be proposed from measured neighbouring cells,
    # but must have four strong boundaries and non-empty artwork of its own.
    for row, cy in enumerate(rows):
        row_boxes = [box for (r, _), box in occupied.items() if r == row]
        rw, rh = np.median([box[2:] for box in row_boxes], axis=0)
        for column, cx in enumerate(columns):
            if (row, column) in occupied or len(occupied) - observed >= maximum_filled:
                continue
            x, y, w, h = round(cx - rw / 2), round(cy - rh / 2), round(rw), round(rh)
            margin_x, margin_y = max(3, round(w * 0.09)), max(3, round(h * 0.08))
            if (
                x - margin_x < 3
                or y - margin_y < 3
                or x + w + margin_x >= width - 3
                or y + h + margin_y >= height - 3
            ):
                continue

            # Camera perspective and rounded corners can shift a neighbouring
            # row's borders. Search a *small* local interval for a supported line
            # rather than demanding edges at the extrapolated coordinates.
            def refine(
                position: int,
                margin: int,
                gradient: np.ndarray,
                axis: int,
                span_start: int,
                span_end: int,
            ) -> int:
                best, best_score = position, -1.0
                for candidate in range(position - margin, position + margin + 1):
                    if axis == 1:
                        values = gradient[
                            span_start:span_end,
                            candidate - 2 : candidate + 3,
                        ].max(axis=1)
                    else:
                        values = gradient[
                            candidate - 2 : candidate + 3,
                            span_start:span_end,
                        ].max(axis=0)
                    score = (
                        float((values > 30).mean())
                        + float(np.minimum(values, 100).mean()) / 500
                        - abs(candidate - position) / margin * 0.04
                    )
                    if score > best_score:
                        best, best_score = candidate, score
                return best

            left = refine(x, margin_x, gx, 1, y + h // 12, y + h - h // 12)
            right = refine(x + w, margin_x, gx, 1, y + h // 12, y + h - h // 12)
            top = refine(y, margin_y, gy, 0, x + w // 12, x + w - w // 12)
            bottom = refine(y + h, margin_y, gy, 0, x + w // 12, x + w - w // 12)
            x, y, w, h = left, top, right - left, bottom - top
            if not (0.48 <= w / h <= 0.82 and 0.8 <= w / rw <= 1.2 and 0.8 <= h / rh <= 1.2):
                continue
            strips = (
                gx[y + h // 12 : y + h - h // 12, x - 3 : x + 4].max(axis=1),
                gx[y + h // 12 : y + h - h // 12, x + w - 3 : x + w + 4].max(axis=1),
                gy[y - 3 : y + 4, x + w // 12 : x + w - w // 12].max(axis=0),
                gy[y + h - 3 : y + h + 4, x + w // 12 : x + w - w // 12].max(axis=0),
            )
            if min(float((strip > 30).mean()) for strip in strips) < 0.60:
                continue
            if float(gray[y + h // 10 : y + h - h // 10, x + w // 10 : x + w - w // 10].std()) < 18:
                continue
            occupied[(row, column)] = (x, y, w, h)
    output = []
    for _key, (x, y, w, h) in sorted(occupied.items()):
        points = np.float32([[x, y], [x + w - 1, y], [x + w - 1, y + h - 1], [x, y + h - 1]])
        points = cv2.transform(points[None], inverse)[0]
        if (
            points[:, 0].min() < 1
            or points[:, 1].min() < 1
            or points[:, 0].max() > width - 2
            or points[:, 1].max() > height - 2
        ):
            continue
        output.append(points)
    return output
