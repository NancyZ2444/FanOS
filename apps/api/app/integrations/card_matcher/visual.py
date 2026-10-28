"""Verify card artwork using local features; scores are not probabilities."""

from __future__ import annotations

import math

import cv2
import numpy as np
from PIL import Image, ImageOps

ENGINE = "sift-homography-v1"


def display_orientation(projected: np.ndarray) -> dict[str, int]:
    """Display-only correction from verified reference → query geometry.

    The points retain reference TL/TR/BR/BL order. Image axes have y pointing
    down, so positive atan2 angles mean clockwise rotation. Never rotate the
    stored crop or the original-image overlay, and do not guess from aspect
    ratio: a landscape card can be intentional. Ambiguous/skewed/reflected
    geometry simply has no orientation hint.
    """
    points = np.asarray(projected, dtype=np.float64)
    if points.shape != (4, 2) or not np.isfinite(points).all():
        return {}
    right = (points[1] - points[0] + points[2] - points[3]) / 2
    down = (points[3] - points[0] + points[2] - points[1]) / 2
    if min(np.linalg.norm(right), np.linalg.norm(down)) < 1e-6:
        return {}
    if right[0] * down[1] - right[1] * down[0] <= 0:
        return {}
    angle = math.degrees(math.atan2(right[1], right[0]))
    quarter_turns = round(angle / 90)
    down_angle = math.degrees(math.atan2(down[1], down[0])) - 90

    def distance(a, b):
        return abs((a - b + 180) % 360 - 180)

    if max(distance(angle, quarter_turns * 90), distance(down_angle, quarter_turns * 90)) > 30:
        return {}
    return {"display_rotation_quarter_turns": (-quarter_turns) % 4}


def features(image: Image.Image) -> dict:
    image = ImageOps.exif_transpose(image).convert("RGB")
    image.thumbnail((1000, 1000))
    gray = cv2.cvtColor(np.asarray(image), cv2.COLOR_RGB2GRAY)
    points, descriptors = cv2.SIFT_create(nfeatures=1400).detectAndCompute(gray, None)
    return {
        "engine": ENGINE,
        "size": list(image.size),
        "points": [list(point.pt) for point in points],
        "descriptors": descriptors.tolist() if descriptors is not None else [],
    }


def similarity(query: dict, reference: dict) -> tuple[float, dict]:
    if len(query["descriptors"]) < 8 or len(reference["descriptors"]) < 8:
        return 0.0, {}
    pairs = cv2.BFMatcher().knnMatch(
        np.asarray(reference["descriptors"], dtype=np.float32),
        np.asarray(query["descriptors"], dtype=np.float32),
        k=2,
    )
    matches = [
        a for pair in pairs if len(pair) == 2 for a, b in [pair] if a.distance < 0.72 * b.distance
    ]
    # A repeated texture must not match many reference points to one query point.
    matches = list({m.trainIdx: m for m in sorted(matches, key=lambda m: -m.distance)}.values())
    if len(matches) < 8:
        return 0.0, {}
    src = np.float32([reference["points"][m.queryIdx] for m in matches])
    dst = np.float32([query["points"][m.trainIdx] for m in matches])
    qwidth, qheight = query["size"]
    # RANSAC measures residuals in query pixels. A fixed four-pixel allowance
    # spans much of a small facial detail in a thumbnail, but little of a large
    # card. Scale the tolerance, retaining a one-pixel localization floor and
    # the existing four-pixel allowance for larger photographs.
    reprojection_tolerance = max(1.0, min(4.0, min(qwidth, qheight) * 0.012))
    transform, mask = cv2.findHomography(src, dst, cv2.RANSAC, reprojection_tolerance)
    if transform is None or mask is None or not np.isfinite(transform).all():
        return 0.0, {}
    inliers = mask.ravel().astype(bool)
    count = int(inliers.sum())
    ratio = count / len(matches)
    width, height = reference["size"]
    coverage = cv2.contourArea(cv2.convexHull(src[inliers])) / (width * height)
    corners = np.float32([[0, 0], [width, 0], [width, height], [0, height]])
    projected = cv2.perspectiveTransform(corners.reshape(1, 4, 2), transform)[0]
    area = abs(cv2.contourArea(projected))
    if (
        count < 8
        or ratio < 0.45
        or coverage < 0.08
        or not cv2.isContourConvex(projected)
        or not 0.12 < area / (qwidth * qheight) < 1.8
    ):
        return 0.0, {}
    score = min(
        0.99, 0.50 + 0.20 * ratio + 0.15 * min(count / 40, 1) + 0.14 * min(coverage / 0.5, 1)
    )
    return float(score), {
        "inliers": count,
        "inlier_ratio": ratio,
        "coverage": coverage,
        **display_orientation(projected),
    }


def approximate_similarity(query: dict, reference: dict) -> tuple[float, dict]:
    """Find distributed, similar artwork for manual review, never card identity.

    Relaxing descriptor distinctiveness is useful for related printed details,
    but also admits accidental matches. Require reciprocal matches, independent
    image locations and a coherent scale/rotation/translation in both images.
    This intentionally uses fewer geometric freedoms than the exact-card path.
    Existing SIFT index entries contain everything this fallback needs.
    """
    if min(len(query["descriptors"]), len(reference["descriptors"])) < 8:
        return 0.0, {}
    qsize = np.asarray(query["size"], dtype=np.float32)
    rsize = np.asarray(reference["size"], dtype=np.float32)
    if not np.isfinite([qsize, rsize]).all() or min(qsize.min(), rsize.min()) <= 0:
        return 0.0, {}
    qdesc = np.asarray(query["descriptors"], dtype=np.float32)
    rdesc = np.asarray(reference["descriptors"], dtype=np.float32)
    matcher = cv2.BFMatcher()

    def distinctive(source, destination):
        return [
            a
            for pair in matcher.knnMatch(source, destination, k=2)
            if len(pair) == 2
            for a, b in [pair]
            if a.distance < 0.86 * b.distance
        ]

    reverse = {(m.trainIdx, m.queryIdx) for m in distinctive(qdesc, rdesc)}
    mutual = [m for m in distinctive(rdesc, qdesc) if (m.queryIdx, m.trainIdx) in reverse]
    source, destination = [], []
    for match in sorted(mutual, key=lambda item: item.distance):
        src = np.asarray(reference["points"][match.queryIdx], dtype=np.float32) / rsize
        dst = np.asarray(query["points"][match.trainIdx], dtype=np.float32) / qsize
        # SIFT can emit several orientations at one physical location. They
        # must not count as independent evidence or inflate the inlier ratio.
        if any(
            np.linalg.norm(src - old_src) < 0.012 or np.linalg.norm(dst - old_dst) < 0.012
            for old_src, old_dst in zip(source, destination, strict=True)
        ):
            continue
        source.append(src)
        destination.append(dst)
    if len(source) < 8:
        return 0.0, {}
    src, dst = np.float32(source), np.float32(destination)
    if not np.isfinite([src, dst]).all():
        return 0.0, {}
    transform, mask = cv2.estimateAffinePartial2D(
        src,
        dst,
        method=cv2.RANSAC,
        ransacReprojThreshold=0.045,
        maxIters=3000,
        confidence=0.99,
        refineIters=10,
    )
    if transform is None or mask is None or not np.isfinite(transform).all():
        return 0.0, {}
    inliers = mask.ravel().astype(bool)
    count = int(inliers.sum())
    ratio = count / len(source)
    if count < 8 or ratio < 0.5:
        return 0.0, {}

    def distribution(points):
        coverage = cv2.contourArea(cv2.convexHull(points))
        span = float(np.ptp(points, axis=0).min())
        cells = len({tuple(np.clip((point * 3).astype(int), 0, 2)) for point in points})
        return coverage, span, cells

    rcoverage, rspan, rcells = distribution(src[inliers])
    qcoverage, qspan, qcells = distribution(dst[inliers])
    # Reject one tiny shared motif, a row of lettering, and repeated texture.
    if min(rcoverage, qcoverage) < 0.06 or min(rspan, qspan) < 0.25 or min(rcells, qcells) < 3:
        return 0.0, {}
    corners = np.float32([[0, 0], [1, 0], [1, 1], [0, 1]])
    projected = cv2.transform(corners.reshape(1, 4, 2), transform)[0]
    area = abs(cv2.contourArea(projected))
    if not 0.4 < area < 1.8:
        return 0.0, {}
    intersection, _ = cv2.intersectConvexConvex(projected, corners)
    inside = float(intersection / area)
    if inside < 0.65:
        return 0.0, {}
    coverage = min(rcoverage, qcoverage)
    score = min(
        0.85, 0.60 + 0.10 * ratio + 0.08 * min(count / 24, 1) + 0.07 * min(coverage / 0.3, 1)
    )
    return float(score), {
        "approximate": 1.0,
        "inliers": count,
        "inlier_ratio": ratio,
        "coverage": rcoverage,
        "query_coverage": qcoverage,
        "spatial_cells": min(rcells, qcells),
        "in_frame_fraction": inside,
        **display_orientation(projected),
    }
