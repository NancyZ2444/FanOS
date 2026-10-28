"""Partly obscured card edges must not turn a measured grid into fixed slots."""

import numpy as np
import pytest
from PIL import Image, ImageDraw

import app.integrations.card_matcher.sleeve_detector as sleeve
from app.integrations.card_matcher.sleeve_detector import detect_sleeve_quadrilaterals


def partly_obscured_grid(columns=3, *, visible_edge=0.30, empty=False):
    paper = (200, 200, 200)
    photo = Image.new("RGB", (80 + columns * 240, 1100), paper)
    draw = ImageDraw.Draw(photo)
    centers = []
    for row in range(3):
        for column in range(columns):
            x, y = 70 + column * 240, 40 + row * 350
            if empty and (row, column) == (0, columns - 1):
                # An empty pocket still has visible rectangular seams.
                draw.rectangle((x, y, x + 180, y + 300), outline=(120, 120, 120), width=2)
                continue
            draw.rectangle((x, y, x + 180, y + 300), fill=(120, 120, 120))
            draw.ellipse((x + 40, y + 70, x + 140, y + 220), fill=(20, 20, 20))
            draw.ellipse((x + 80, y + 170, x + 160, y + 260), fill=(240, 240, 240))
            centers.append((x + 90, y + 150))

    # A broad soft glare erases most of the top border without creating a
    # replacement horizontal edge. Other cards still establish the layout.
    x, y = 70 + (columns - 1) * 240, 40
    array = np.asarray(photo).astype(float)
    for py in range(y - 20, y + 50):
        alpha = max(0, min(1, (y + 50 - py) / 50))
        start, end = x + int(180 * visible_edge), x + 200
        array[py, start:end] = array[py, start:end] * (1 - alpha) + 200 * alpha
    return array.astype(np.uint8), centers


@pytest.mark.parametrize("columns", [2, 3])
def test_grid_recovers_card_with_one_partially_visible_edge(columns):
    rgb, expected_centers = partly_obscured_grid(columns)
    polygons = detect_sleeve_quadrilaterals(rgb)
    assert len(polygons) == len(expected_centers)
    centers = [points.mean(axis=0) for points in polygons]
    for center in expected_centers:
        assert any(np.linalg.norm(actual - center) < 15 for actual in centers)
    assert all(0.50 < np.ptp(points[:, 0]) / np.ptp(points[:, 1]) < 0.70 for points in polygons)


def test_grid_does_not_invent_card_without_enough_fourth_edge_evidence():
    rgb, _ = partly_obscured_grid(visible_edge=0.10)
    assert len(detect_sleeve_quadrilaterals(rgb)) == 8


def test_grid_does_not_fill_empty_pocket_even_with_visible_seams():
    rgb, centers = partly_obscured_grid(empty=True)
    assert len(detect_sleeve_quadrilaterals(rgb)) == len(centers) == 8


@pytest.mark.parametrize("empty", [False, True])
def test_three_contour_seeds_need_independent_evidence_for_fourth_card(monkeypatch, empty):
    rgb, _ = partly_obscured_grid(columns=2)
    rgb = rgb[:740].copy()
    if empty:
        rgb[392:689, 312:489] = 200
    seeds = [
        np.float32([[x, y], [x + 180, y], [x + 180, y + 300], [x, y + 300]])
        for x, y in [(70, 40), (310, 40), (70, 390)]
    ]
    # The ordinary contour detector supplied these three measured rectangles;
    # sleeve morphology supplied none. The fourth cell needs its own image
    # evidence, even though three seeds predict its location unambiguously.
    monkeypatch.setattr(sleeve.cv2, "findContours", lambda *args: ([], None))
    polygons = detect_sleeve_quadrilaterals(rgb, supplemental_points=seeds)
    assert len(polygons) == (0 if empty else 4)
    if polygons:
        assert np.linalg.norm(polygons[-1].mean(axis=0) - [400, 540]) < 15
