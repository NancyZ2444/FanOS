"""Thumbnail matching needs geometric precision as well as plausible features."""

import io

import numpy as np
import pytest
from conftest import scan_artwork
from PIL import Image, ImageEnhance

from app.integrations.card_matcher.visual import features, similarity


def locally_similar_features(seed, scale=1):
    """Descriptors agree, but locations are only approximately related.

    Identical descriptors deliberately isolate the geometric verification step.
    The same absolute localization errors occupy a substantial part of a tiny
    motif, but are ordinary localization noise in a much larger photograph.
    """
    random = np.random.default_rng(seed)
    locations = random.uniform([20, 20], [80, 110], size=(14, 2)).astype(np.float32)
    localization_error = random.normal(0, 1.6, size=locations.shape)
    descriptors = random.normal(size=(14, 128)).astype(np.float32).tolist()
    reference = {
        "engine": "sift-homography-v1",
        "size": [100 * scale, 150 * scale],
        "points": (locations * scale).tolist(),
        "descriptors": descriptors,
    }
    query = {
        "engine": "sift-homography-v1",
        "size": [90 * scale, 135 * scale],
        "points": (
            locations * 0.8 * scale + np.array([3, 5]) * scale + localization_error
        ).tolist(),
        "descriptors": descriptors,
    }
    return query, reference


@pytest.mark.parametrize("seed", [7, 19])
def test_similar_local_descriptors_do_not_establish_thumbnail_card_identity(seed):
    query, reference = locally_similar_features(seed)
    score, evidence = similarity(query, reference)
    assert score == 0
    assert evidence == {}


@pytest.mark.parametrize("seed", [7, 19])
def test_large_photo_keeps_tolerance_for_small_absolute_localization_errors(seed):
    query, reference = locally_similar_features(seed, scale=10)
    score, evidence = similarity(query, reference)
    assert score > 0.75
    assert evidence["inliers"] >= 12
    assert evidence["coverage"] > 0.15


@pytest.mark.parametrize("width", [70, 100, 160])
@pytest.mark.parametrize("rotation", [0, 90])
def test_same_print_matches_after_thumbnail_resize_rotation_exposure_and_jpeg(width, rotation):
    original = scan_artwork(17)
    thumbnail = original.resize(
        (width, round(width * original.height / original.width)), Image.Resampling.LANCZOS
    ).rotate(rotation, expand=True)
    thumbnail = ImageEnhance.Brightness(thumbnail).enhance(0.85)
    buffer = io.BytesIO()
    thumbnail.save(buffer, format="JPEG", quality=85)
    with Image.open(io.BytesIO(buffer.getvalue())) as compressed:
        score, evidence = similarity(features(compressed), features(original))
    assert score >= 0.90
    assert evidence["inliers"] >= 30
    assert evidence["coverage"] > 0.30
