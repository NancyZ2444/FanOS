"""Related artwork is reviewable evidence, not verified card identity."""

from types import SimpleNamespace

import numpy as np
import pytest
from PIL import Image, ImageDraw

from app.integrations.card_matcher import adapter
from app.integrations.card_matcher.visual import approximate_similarity, features, similarity


def corresponding_features(seed=11):
    rng = np.random.default_rng(seed)
    locations = rng.uniform([0.12, 0.12], [0.88, 0.88], (30, 2))
    descriptors = rng.uniform(0, 255, (30, 128)).astype(np.float32).tolist()
    reference = {
        "size": [100, 150],
        "points": (locations * [100, 150]).tolist(),
        "descriptors": descriptors,
    }
    query = {
        "size": [100, 150],
        "points": ((locations + rng.normal(0, 0.018, (30, 2))) * [100, 150]).tolist(),
        "descriptors": descriptors,
    }
    return query, reference


@pytest.mark.parametrize("seed", [11, 27, 91])
def test_approximately_aligned_details_offer_review_without_claiming_card_identity(seed):
    query, reference = corresponding_features(seed)
    assert similarity(query, reference) == (0.0, {})
    score, evidence = approximate_similarity(query, reference)
    assert 0.6 <= score <= 0.85
    assert evidence["approximate"] == 1.0
    assert evidence["inliers"] >= 20
    assert evidence["spatial_cells"] >= 6


@pytest.mark.parametrize(
    "shape", ["tiny_motif", "lettering_line", "mostly_off_card", "small_patch"]
)
def test_local_or_implausibly_positioned_agreement_does_not_supply_candidates(shape):
    query, reference = corresponding_features()
    points = np.asarray(reference["points"]) / reference["size"]
    if shape == "tiny_motif":
        src = points * 0.2 + 0.4
        dst = src
    elif shape == "lettering_line":
        src = points * [1, 0.08]
        dst = src
    elif shape == "mostly_off_card":
        src = points * 0.55
        dst = src + [0.55, 0]
    else:
        src = points
        dst = src * 0.5 + 0.1
    reference["points"] = (src * reference["size"]).tolist()
    query["points"] = (dst * query["size"]).tolist()
    assert approximate_similarity(query, reference) == (0.0, {})


def test_multiple_sift_orientations_at_five_locations_are_not_thirty_independent_matches():
    query, reference = corresponding_features()
    repeated = np.repeat(np.asarray(reference["points"])[::6], 6, axis=0).tolist()
    query["points"] = repeated
    reference["points"] = repeated
    assert approximate_similarity(query, reference) == (0.0, {})


def test_corresponding_descriptors_scattered_without_geometric_agreement_are_rejected():
    query, reference = corresponding_features()
    query["points"] = (np.random.default_rng(71).uniform(0, 1, (30, 2)) * query["size"]).tolist()
    assert approximate_similarity(query, reference) == (0.0, {})


def test_unrelated_textured_prints_and_blank_cards_do_not_get_filler_candidates():
    def artwork(seed):
        rng = np.random.default_rng(seed)
        image = Image.new("RGB", (200, 300), "#e8e4df")
        draw = ImageDraw.Draw(image)
        for _ in range(100):
            x, y = rng.integers([5, 5], [180, 280])
            draw.ellipse(
                (x, y, x + 10, y + 10), fill=tuple(rng.integers(0, 200, 3)), outline="black"
            )
        return features(image)

    reference = artwork(20)
    query = artwork(39)
    assert min(len(reference["descriptors"]), len(query["descriptors"])) > 50
    assert approximate_similarity(query, reference) == (0.0, {})
    assert approximate_similarity(features(Image.new("RGB", (200, 300), "white")), reference) == (
        0.0,
        {},
    )


def test_rank_keeps_all_verified_artwork_ahead_of_similar_artwork(monkeypatch):
    matcher = object.__new__(adapter.CardMatcherAdapter)
    matcher.settings = SimpleNamespace(card_matcher_max_candidates=3)
    rows = [
        {"card_id": "related", "visual": "related"},
        {"card_id": "verified_low", "visual": "verified_low"},
        {"card_id": "verified_high", "visual": "verified_high"},
        {"card_id": "unrelated", "visual": "unrelated"},
    ]
    monkeypatch.setattr(matcher, "indexed", lambda known: rows)
    monkeypatch.setattr(adapter, "features", lambda image: {})
    monkeypatch.setattr(
        adapter,
        "similarity",
        lambda query, reference: (
            {"verified_low": 0.70, "verified_high": 0.96}.get(reference, 0),
            {},
        ),
    )
    fallback_calls = []

    def fallback(query, reference):
        fallback_calls.append(reference)
        return (0.85, {"approximate": 1.0}) if reference == "related" else (0.0, {})

    monkeypatch.setattr(adapter, "approximate_similarity", fallback)
    ranked = matcher.rank(Image.new("RGB", (2, 2)), {})
    assert [item["card_id"] for item in ranked] == ["verified_high", "verified_low", "related"]
    assert fallback_calls == ["related", "unrelated"]
    assert ranked[-1]["feature_scores"]["approximate"] == 1.0
