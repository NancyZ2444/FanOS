"""Reference indexing must preserve artwork and still reject multi-card photos."""

import io

import pytest
from PIL import Image, ImageDraw

from app.integrations.card_matcher.adapter import CardMatcherAdapter, DetectedRegion
from app.integrations.card_matcher.reference_geometry import select_reference_region


def _regions(image):
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return CardMatcherAdapter.detect(buffer.getvalue(), require_person=False)


def _fragment_artwork():
    image = Image.new("RGB", (211, 335), "#d0bdaf")
    draw = ImageDraw.Draw(image)
    # Long tapered print shapes resemble hair and an arm, not physical cards.
    draw.polygon([(5, 28), (84, 19), (31, 168), (3, 176)], fill="#28201e")
    draw.polygon([(172, 19), (195, 19), (207, 32), (207, 133)], fill="#3a2420")
    return image


@pytest.mark.parametrize("rotation", [0, 90, 180, 270])
def test_tight_artwork_fragments_do_not_replace_the_complete_reference(rotation):
    image = _fragment_artwork().rotate(rotation, expand=True)
    regions = _regions(image)
    # Exercise actual contour extraction, rather than supplying pre-labelled
    # bad geometry to the guard. The original indexer rejects these fragments.
    assert len(regions) >= 2
    assert select_reference_region(regions, image.size) is None


def test_table_single_card_keeps_its_detected_crop():
    photo = Image.new("RGB", (600, 600), "#242424")
    ImageDraw.Draw(photo).rectangle((120, 50, 360, 410), fill="#dabdb0")
    regions = _regions(photo)

    selected = select_reference_region(regions, photo.size)

    assert selected is not None
    assert selected.x == pytest.approx(0.2, abs=0.01)
    assert selected.y == pytest.approx(50 / 600, abs=0.01)
    assert selected.width == pytest.approx(240 / 600, abs=0.01)
    assert selected.height == pytest.approx(360 / 600, abs=0.01)


def test_card_shaped_photo_with_two_real_cards_is_still_rejected():
    photo = Image.new("RGB", (600, 900), "#242424")
    draw = ImageDraw.Draw(photo)
    draw.rectangle((120, 50, 360, 410), fill="#dabdb0")
    draw.rectangle((120, 480, 360, 840), fill="#ada0d0")

    with pytest.raises(ValueError, match="建库照片需仅包含一张小卡"):
        select_reference_region(_regions(photo), photo.size)


def test_separate_perspective_card_is_not_ignored_as_small_artwork():
    photo = Image.new("RGB", (600, 900), "#242424")
    draw = ImageDraw.Draw(photo)
    draw.polygon([(60, 50), (300, 50), (300, 410), (60, 410)], fill="#dabdb0")
    draw.polygon([(370, 500), (530, 510), (490, 760), (450, 750)], fill="#ada0d0")
    regions = _regions(photo)
    assert len(regions) == 2

    with pytest.raises(ValueError, match="建库照片需仅包含一张小卡"):
        select_reference_region(regions, photo.size)


def test_small_print_fragments_inside_the_selected_card_can_be_ignored():
    artwork = _fragment_artwork()
    fragments = _regions(artwork)
    assert len(fragments) >= 2
    # Supply a complete outline together with the real interior detections.
    # Detector NMS normally removes these contained fragments before indexing.
    card = DetectedRegion(
        0,
        0,
        1,
        1,
        artwork,
        [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 1, "y": 1}, {"x": 0, "y": 1}],
        artwork.size,
    )

    assert select_reference_region([card, *fragments], artwork.size) is card


def test_perspective_card_retains_its_crop():
    photo = Image.new("RGB", (600, 700), "#242424")
    ImageDraw.Draw(photo).polygon([(80, 90), (380, 110), (410, 580), (90, 610)], fill="#dabdb0")

    selected = select_reference_region(_regions(photo), photo.size)

    assert selected is not None
    assert selected.x < 0.15
    assert selected.width > 0.5
    assert selected.height > 0.7
    assert selected.width * selected.height < 0.6


def test_small_invalid_fragments_do_not_turn_a_square_scene_into_a_reference():
    photo = Image.new("RGB", (335, 335), "#d0bdaf")
    photo.paste(_fragment_artwork(), (0, 0))

    with pytest.raises(ValueError, match="建库照片需仅包含一张小卡"):
        select_reference_region(_regions(photo), photo.size)


def test_large_uncertain_shape_is_not_replaced_with_the_whole_photo():
    photo = Image.new("RGB", (400, 600), "#d0bdaf")
    # A large, severely tapered object may be a strongly skewed card. Ask for
    # an explicit crop instead of silently treating its background as artwork.
    ImageDraw.Draw(photo).polygon([(20, 70), (370, 35), (210, 520), (70, 550)], fill="#28201e")
    regions = _regions(photo)
    assert len(regions) == 1

    with pytest.raises(ValueError, match="建库照片需仅包含一张小卡"):
        select_reference_region(regions, photo.size)
