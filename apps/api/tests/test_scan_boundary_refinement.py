"""Check physical card corners rather than accepting the right card count."""

import cv2
import numpy as np
import pytest
from PIL import Image, ImageDraw

from app.integrations.card_matcher.card_boundary_refiner import refine_card_boundary


def sleeved_card(*, printed_border=False, perspective=False):
    photo = Image.new("RGB", (800, 1100), (40, 45, 50))
    draw = ImageDraw.Draw(photo)
    outer = np.float32([[100, 80], [700, 80], [700, 1020], [100, 1020]])
    inner = np.float32([[125, 110], [675, 110], [675, 995], [125, 995]])
    margin = (245, 245, 245) if printed_border else (50, 55, 60)
    draw.rectangle((100, 80, 700, 1020), fill=margin, outline=(150, 155, 160), width=2)
    draw.rounded_rectangle((125, 110, 675, 995), radius=24, fill=(180, 150, 130))
    draw.ellipse((250, 200, 500, 500), fill=(90, 65, 45))
    draw.polygon([(220, 900), (350, 520), (580, 900)], fill=(50, 95, 145))
    rgb = np.asarray(photo)
    if perspective:
        source = np.float32([[0, 0], [799, 0], [799, 1099], [0, 1099]])
        destination = np.float32([[20, 10], [780, 30], [760, 1070], [40, 1090]])
        transform = cv2.getPerspectiveTransform(source, destination)
        rgb = cv2.warpPerspective(rgb, transform, (800, 1100), borderValue=(40, 45, 50))
        outer = cv2.perspectiveTransform(outer[None], transform)[0]
        inner = cv2.perspectiveTransform(inner[None], transform)[0]
    return rgb, outer, inner


@pytest.mark.parametrize("perspective", [False, True])
def test_refinement_follows_printed_card_edges_inside_transparent_sleeve(perspective):
    rgb, outer, expected = sleeved_card(perspective=perspective)
    refined = refine_card_boundary(rgb, outer)
    assert np.linalg.norm(refined - expected, axis=1).max() < 6
    assert abs(cv2.contourArea(refined)) / abs(cv2.contourArea(outer)) >= 0.85
    assert all(cv2.pointPolygonTest(outer, tuple(point), False) >= 0 for point in refined)


def test_printed_white_border_is_part_of_card_and_must_remain():
    rgb, outer, _ = sleeved_card(printed_border=True)
    np.testing.assert_array_equal(refine_card_boundary(rgb, outer), outer)


def test_transparent_edge_does_not_allow_other_printed_borders_to_be_removed():
    rgb, outer, _ = sleeved_card(printed_border=True)
    rgb = rgb.copy()
    # Only the left band is transparent; the top, right and bottom bands are
    # opaque printed white borders and belong to the physical card.
    rgb[82:1019, 102:125] = (50, 55, 60)
    refined = refine_card_boundary(rgb, outer)
    np.testing.assert_allclose(refined[[1, 2]], outer[[1, 2]], atol=0.01)
    np.testing.assert_allclose(refined[:, 1], outer[:, 1], atol=0.01)
    assert np.all(np.abs(refined[[0, 3], 0] - 125) < 6)
    np.testing.assert_allclose(refine_card_boundary(rgb, refined), refined, atol=0.01)


def test_continuous_clear_segment_recovers_sleeve_with_majority_glare():
    rgb, outer, expected = sleeved_card()
    rgb = rgb.copy()
    # The lower 65% of the left sleeve margin is strongly reflective. The
    # uninterrupted upper clear section still establishes its own transparency.
    rgb[round(110 + 885 * 0.35) : 995, 103:124] = (245, 245, 245)
    refined = refine_card_boundary(rgb, outer)
    assert np.linalg.norm(refined - expected, axis=1).max() < 6


def test_additive_local_glare_preserves_physical_printed_card_edge():
    rgb, outer, expected = sleeved_card()
    rgb = rgb.copy()
    # The same neutral reflected light falls on the sleeve and nearby artwork.
    # Its broad gray reflection develops a short saturated white highlight;
    # the physical card boundary stays fixed throughout the photograph.
    for y in range(82, 1019):
        extra = 100 + 115 * np.exp(-0.5 * ((y - 790) / 120) ** 2)
        rgb[y, 102:190] = np.clip(rgb[y, 102:190].astype(float) + extra, 0, 255).astype(np.uint8)
    refined = refine_card_boundary(rgb, outer)
    assert np.linalg.norm(refined - expected, axis=1).max() < 6
    np.testing.assert_allclose(refine_card_boundary(rgb, refined), refined, atol=0.01)


def test_repeated_refinement_does_not_keep_trimming_card():
    rgb, outer, _ = sleeved_card()
    refined = refine_card_boundary(rgb, outer)
    np.testing.assert_allclose(refine_card_boundary(rgb, refined), refined, atol=0.01)


def test_small_grid_card_is_outside_large_single_card_refinement_scope():
    rgb, outer, _ = sleeved_card()
    canvas = np.full((2200, 1600, 3), 40, dtype=np.uint8)
    canvas[: rgb.shape[0], : rgb.shape[1]] = rgb
    np.testing.assert_array_equal(refine_card_boundary(canvas, outer), outer)
