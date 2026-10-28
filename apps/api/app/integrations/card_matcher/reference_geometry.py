"""Choose reference-card geometry without indexing small artwork fragments.

This guard is only for reference indexing. It does not alter public detection
or infer crop provenance from an upload URL. A card-shaped input may retain its
whole artwork when the detector found only small, nonrectangular fragments.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Protocol, TypeVar

import cv2
import numpy as np

_SINGLE_CARD_ERROR = "建库照片需仅包含一张小卡，请先裁剪正面图片"


class _Region(Protocol):
    x: float
    y: float
    width: float
    height: float
    corners: list[dict[str, float]] | None


_RegionT = TypeVar("_RegionT", bound=_Region)


def _geometry(region: _Region, image_size: tuple[int, int]) -> tuple[bool, float]:
    """Return plausible-card geometry and its fraction of the original image."""
    if region.corners is None:
        # The existing detector explicitly returns this when no contour exists.
        # A partial box without corners provides no evidence for a safe crop.
        full_image = np.allclose((region.x, region.y, region.width, region.height), (0, 0, 1, 1))
        return bool(full_image), 1.0
    try:
        points = np.float32([[point["x"], point["y"]] for point in region.corners])
    except (KeyError, TypeError, ValueError):
        return False, 1.0
    if (
        points.shape != (4, 2)
        or not np.isfinite(points).all()
        or np.any(points < 0)
        or np.any(points > 1)
    ):
        return False, 1.0
    width, height = image_size
    points *= np.float32([width - 1, height - 1])
    if not cv2.isContourConvex(points):
        return False, 1.0
    area = abs(cv2.contourArea(points)) / (width * height)
    sides = np.roll(points, -1, axis=0) - points
    lengths = np.linalg.norm(sides, axis=1)
    if lengths.min() < 1:
        return False, 1.0
    # A long tapered hair/arm contour can satisfy the detector's width/height
    # ratio while having almost collinear corners or very unequal opposite
    # edges. Ordinary perspective cards retain four recognizable corners.
    cosines = np.abs(np.sum(sides * np.roll(sides, -1, axis=0), axis=1)) / (
        lengths * np.roll(lengths, -1)
    )
    opposite = lengths / np.roll(lengths, 2)
    plausible = bool(cosines.max() <= 0.45 and opposite.max() <= 1.8)
    return plausible, area


def _contains_fragment(card: _Region, fragment: _Region) -> bool:
    """Ignore artwork only within the selected card's actual four edges."""
    # Geometry validation has already established finite, convex corners for
    # every small fragment. A cornerless accepted region is the entire image.
    outer = (
        np.float32([[point["x"], point["y"]] for point in card.corners])
        if card.corners is not None
        else np.float32([[0, 0], [1, 0], [1, 1], [0, 1]])
    )
    return fragment.corners is not None and all(
        cv2.pointPolygonTest(outer, (float(point["x"]), float(point["y"])), False) >= 0
        for point in fragment.corners
    )


def select_reference_region(
    regions: Sequence[_RegionT], image_size: tuple[int, int]
) -> _RegionT | None:
    """Return one reliable region, or None to preserve a tight complete image.

    Multiple plausible cards remain an error, even when the photograph itself
    has a card aspect ratio. Whole-image fallback is restricted to small invalid
    fragments: it must not swallow a large, uncertain card or a table scene.
    The caller must use the EXIF-oriented image size and retain that same image
    when this function returns None.
    """
    width, height = image_size
    if not regions or min(width, height) < 2:
        raise ValueError(_SINGLE_CARD_ERROR)
    plausible = []
    fragments = []
    fragment_areas = []
    for region in regions:
        valid, area = _geometry(region, image_size)
        if valid:
            plausible.append(region)
        else:
            fragments.append(region)
            fragment_areas.append(area)
    if len(plausible) > 1:
        raise ValueError(_SINGLE_CARD_ERROR)
    small_fragments = all(area <= 0.2 for area in fragment_areas) and sum(fragment_areas) <= 0.25
    if plausible and small_fragments and all(
        _contains_fragment(plausible[0], fragment) for fragment in fragments
    ):
        return plausible[0]
    ratio = min(width, height) / max(width, height)
    if not plausible and small_fragments and 0.45 <= ratio <= 0.88:
        return None
    raise ValueError(_SINGLE_CARD_ERROR)
