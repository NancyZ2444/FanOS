"""Regressions for choosing a complete card outline from overlapping proposals."""

import numpy as np

from app.integrations.card_matcher.card_geometry import (
    CardBoundaryScorer,
    distinct_quadrilaterals,
    touches_photo_frame,
)


def test_one_corner_on_two_photo_sides_is_a_photo_frame():
    # Only the first vertex touches the photograph, but it meets both its top
    # and left sides. Counting vertices previously let this outer frame win.
    photo_frame = np.float32([[0, 0], [370, 30], [365, 570], [45, 565]])
    assert touches_photo_frame(photo_frame, (400, 600))

    # A card resting against just one photograph edge is a different case.
    one_side = np.float32([[0, 50], [350, 50], [350, 550], [0, 550]])
    assert not touches_photo_frame(one_side, (400, 600))


def test_textured_background_does_not_replace_the_actual_card_edge():
    rng = np.random.default_rng(104)
    background = np.clip(rng.normal(55, 18, (600, 400)), 0, 255).astype(np.uint8)
    image = np.repeat(background[:, :, None], 3, axis=2)
    image[38:563, 48:353] = (155, 165, 175)
    # Interior print gives the scene content without drawing a second border.
    image[190:390, 140:260] = (220, 175, 145)
    card = np.float32([[48, 38], [352, 38], [352, 562], [48, 562]])
    background_frame = np.float32([[30, 38], [352, 38], [352, 562], [30, 562]])

    selected = distinct_quadrilaterals(
        [background_frame, card],
        (400, 600),
        quality=CardBoundaryScorer(image),
    )

    assert len(selected) == 1
    np.testing.assert_allclose(selected[0], card)


def test_partial_artwork_line_does_not_crop_the_top_of_a_card():
    image = np.full((600, 400, 3), 70, dtype=np.uint8)
    image[40:561, 40:361] = 140
    # The real upper edge has alternating light/dark print. Its contrast changes
    # direction, but the entire edge is visible. An interior bright decoration
    # has stronger contrast locally and must not become a replacement top edge.
    for x in range(40, 361, 20):
        image[40:61, x : min(x + 20, 361)] = 20 if (x // 20) % 2 else 120
    image[76:117, 140:251] = 250
    card = np.float32([[40, 40], [360, 40], [360, 560], [40, 560]])
    cropped_head = np.float32([[40, 76], [360, 76], [360, 560], [40, 560]])

    selected = distinct_quadrilaterals(
        [cropped_head, card],
        (400, 600),
        quality=CardBoundaryScorer(image),
    )

    assert len(selected) == 1
    np.testing.assert_allclose(selected[0], card)
