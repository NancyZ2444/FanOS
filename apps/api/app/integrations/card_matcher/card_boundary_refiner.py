"""Conservative printed-card refinement inside a visible transparent sleeve.

Two separated, continuous boundaries on at least two sides are required. Each
side that moves must have its own strip resembling the exterior more than the
artwork; evidence on one edge cannot remove another edge's printed border.
"""

from __future__ import annotations

from functools import partial

import cv2
import numpy as np


def _sample_strip(array, offset, *, axis, base, inward, start, end):
    position = base + inward * offset
    if axis == 1:
        return array[start:end, position - 2 : position + 3]
    return np.swapaxes(array[position - 2 : position + 3, start:end], 0, 1)


def _transparent_margin(margin, outside, inside):
    outside_difference = np.linalg.norm(margin - outside, axis=1)
    inside_difference = np.linalg.norm(margin - inside, axis=1)
    if np.median(inside_difference) >= 10 and np.median(outside_difference) < max(
        16, np.median(inside_difference) * 0.65
    ):
        return True

    # A local reflection may cover most of a clear strip. Require a continuous
    # part of this same edge to support transparency, not scattered good pixels
    # or evidence borrowed from another edge.
    direct_run = reflected_run = 0
    reflected_lightness = []
    neutral_highlight = (margin[:, 0] > 245) & (np.linalg.norm(margin[:, 1:] - 128, axis=1) < 6)
    has_highlight = 0.03 <= float(neutral_highlight.mean()) <= 0.40
    for indexes in np.array_split(np.arange(len(margin)), 20):
        out_distance = float(np.median(outside_difference[indexes]))
        in_distance = float(np.median(inside_difference[indexes]))
        direct = in_distance >= 10 and out_distance < max(16, in_distance * 0.65)
        direct_run = direct_run + 1 if direct else 0
        if direct_run >= 6:
            return True
        local_margin, local_outside, local_inside = (
            np.median(values[indexes], axis=0) for values in (margin, outside, inside)
        )
        # Additive, neutral glare raises a clear strip's lightness while its
        # chroma stays close to the exterior. A sustained intermediate tone,
        # substantial variation and a *localized* clipped highlight distinguish
        # that case from a constant opaque white printed rim.
        reflected = (
            has_highlight
            and local_outside[0] + 10 < local_margin[0] < local_inside[0] - 10
            and np.linalg.norm(local_margin[1:] - local_outside[1:]) < 10
        )
        if reflected:
            reflected_run += 1
            reflected_lightness.append(local_margin[0])
        else:
            reflected_run = 0
            reflected_lightness = []
        if reflected_run >= 10 and np.ptp(reflected_lightness) >= 25:
            return True
    return False


def refine_card_boundary(rgb: np.ndarray, points: np.ndarray) -> np.ndarray:
    """Tighten a large isolated card only when sleeve-edge evidence is present.

    Search offsets are bounds, not prescribed insets. Missing or ambiguous
    evidence returns the original quadrilateral. The caller should invoke this
    once, after selecting a single card, before rectifying its final crop.
    """
    original = np.asarray(points, dtype=np.float32)
    image_h, image_w = rgb.shape[:2]
    area = abs(cv2.contourArea(original))
    if area < image_w * image_h * 0.40 or not cv2.isContourConvex(original):
        return original
    if (
        original[:, 0].min() < 0
        or original[:, 1].min() < 0
        or original[:, 0].max() > image_w - 1
        or original[:, 1].max() > image_h - 1
    ):
        return original
    lengths = np.linalg.norm(np.roll(original, -1, axis=0) - original, axis=1)
    card_w, card_h = max(lengths[0], lengths[2]), max(lengths[1], lengths[3])
    scale = min(1.0, 1600 / max(card_w, card_h))
    width, height = round(card_w * scale), round(card_h * scale)
    if min(width, height) < 100:
        return original
    pad = max(8, round(max(width, height) * 0.10))
    target = np.float32(
        [[pad, pad], [pad + width, pad], [pad + width, pad + height], [pad, pad + height]]
    )
    transform = cv2.getPerspectiveTransform(original, target)
    rectified = cv2.warpPerspective(rgb, transform, (width + 2 * pad, height + 2 * pad))
    gray = cv2.GaussianBlur(cv2.cvtColor(rectified, cv2.COLOR_RGB2GRAY), (5, 5), 0)
    gx = np.abs(cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3))
    gy = np.abs(cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3))
    lab = cv2.cvtColor(rectified, cv2.COLOR_RGB2LAB).astype(np.float32)
    sides = (
        (gy, 0, pad, height, width, 1),
        (gx, 1, pad + width, width, height, -1),
        (gy, 0, pad + height, height, width, -1),
        (gx, 1, pad, width, height, 1),
    )
    shifts = [0, 0, 0, 0]
    paired_sides = 0
    transparent_sides = 0
    for side, (gradient, axis, base, depth, length, inward) in enumerate(sides):
        start, end = pad + round(length * 0.06), pad + round(length * 0.94)

        sample = partial(_sample_strip, axis=axis, base=base, inward=inward, start=start, end=end)

        # Outward samples may establish a sleeve's outer edge, but can never
        # enlarge the result. The nearest 6% at each end excludes round corners.
        scores = []
        for offset in range(-round(depth * 0.06), round(depth * 0.09) + 1):
            values = sample(gradient, offset).max(axis=1)
            strength = float(np.minimum(values, 100).mean()) / 100
            support = float((values > 20).mean())
            scores.append((strength + support, offset, support, strength))
        peaks = []
        separation = max(5, round(depth * 0.008))
        for item in sorted(scores, reverse=True):
            if not any(abs(item[1] - peak[1]) < separation for peak in peaks):
                # A five-pixel support band creates a plateau around an edge.
                # Use its centre, not its inward end, to retain the card rim.
                plateau = [
                    entry[1]
                    for entry in scores
                    if abs(entry[1] - item[1]) < separation and entry[0] >= item[0] * 0.98
                ]
                peaks.append((item[0], round(float(np.median(plateau))), item[2], item[3]))
            if len(peaks) == 12:
                break
        best = peaks[0]
        eligible = [
            item
            for item in peaks
            if item[2] >= max(0.75, best[2] * 0.80) and item[3] >= max(0.45, best[3] * 0.65)
        ]
        if not eligible:
            continue
        inner = max(eligible, key=lambda item: item[1])
        outer = [
            item
            for item in peaks
            if inner[1] - item[1] >= max(8, depth * 0.012) and item[2] >= 0.65 and item[3] >= 0.35
        ]
        if not outer:
            continue
        outer_edge = max(outer, key=lambda item: item[0])
        paired_sides += 1
        margin = sample(lab, round((outer_edge[1] + inner[1]) / 2)).mean(axis=1)
        outside = sample(lab, outer_edge[1] - 6).mean(axis=1)
        inside = sample(lab, inner[1] + 6).mean(axis=1)
        transparent = _transparent_margin(margin, outside, inside)
        if transparent:
            transparent_sides += 1
        # Ignore tiny subpixel/gradient-band changes. This also prevents an
        # already-refined printed border from creeping inward on repeated use.
        if transparent and inner[1] > max(4, depth * 0.005):
            shifts[side] = inner[1]
    if paired_sides < 2 or transparent_sides < 1 or not any(shifts):
        return original
    top, right, bottom, left = shifts
    refined = np.float32(
        [
            [pad + left, pad + top],
            [pad + width - right, pad + top],
            [pad + width - right, pad + height - bottom],
            [pad + left, pad + height - bottom],
        ]
    )
    refined = cv2.perspectiveTransform(refined[None], np.linalg.inv(transform))[0]
    if abs(cv2.contourArea(refined)) / area < 0.85:
        return original
    return refined
