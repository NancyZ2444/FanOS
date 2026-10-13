"""Verify card artwork using local features; scores are not probabilities."""

from __future__ import annotations

import cv2
import numpy as np
from PIL import Image, ImageOps

ENGINE = "sift-homography-v1"


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
    transform, mask = cv2.findHomography(src, dst, cv2.RANSAC, 4.0)
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
    qwidth, qheight = query["size"]
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
    return float(score), {"inliers": count, "inlier_ratio": ratio, "coverage": coverage}
