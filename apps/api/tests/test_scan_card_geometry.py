"""Complete card bounds, not just counts, on textured and framed photographs."""

import io

import numpy as np
import pytest
from conftest import scan_artwork
from PIL import Image, ImageDraw

from app.integrations.card_matcher.adapter import CardMatcherAdapter


def encode(image, quality=85):
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=quality)
    return buffer.getvalue()


def textured_table(size):
    width, height = size
    noise = np.random.default_rng(82).normal(0, 5, (height, width, 1))
    return Image.fromarray(np.uint8(np.clip(np.full((height, width, 3), 72) + noise, 0, 255)))


def paste_rounded(scene, xy, size, seed):
    artwork = scan_artwork(seed).resize(size)
    mask = Image.new("L", size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=16, fill=255)
    scene.paste(artwork, xy, mask)


def assert_bounds(regions, size, boxes):
    assert len(regions) == len(boxes)
    observed = [
        (r.x * size[0], r.y * size[1], r.width * size[0], r.height * size[1]) for r in regions
    ]

    def iou(a, b):
        x, y, w, h = a
        bx, by, bw, bh = b
        intersection = max(0, min(x + w, bx + bw) - max(x, bx)) * max(
            0, min(y + h, by + bh) - max(y, by)
        )
        return intersection / (w * h + bw * bh - intersection)

    for x, y, width, height in boxes:
        assert max(iou((x, y, width, height), box) for box in observed) >= 0.8, (boxes, observed)


def test_photograph_border_cannot_swallow_a_smaller_card(allow_synthetic_portraits):
    scene = textured_table((536, 954))
    ImageDraw.Draw(scene).rectangle((1, 1, 533, 951), outline="white", width=2)
    paste_rounded(scene, (148, 321), (220, 337), 17)
    regions = CardMatcherAdapter.detect(encode(scene))
    assert_bounds(regions, scene.size, [(148, 321, 220, 337)])


@pytest.mark.parametrize("gap", [3, 12])
def test_adjacent_rounded_cards_do_not_become_one_outer_frame(allow_synthetic_portraits, gap):
    scene = textured_table((720, 1000))
    boxes = []
    draw = ImageDraw.Draw(scene)
    draw.rectangle((95, 95, 575 + gap, 795 + gap), outline="#a0a0a0", width=2)
    for row in range(2):
        for column in range(2):
            x, y = 100 + column * (230 + gap), 100 + row * (340 + gap)
            paste_rounded(scene, (x, y), (230, 340), 21 + row * 2 + column)
            boxes.append((x, y, 230, 340))
    assert_bounds(CardMatcherAdapter.detect(encode(scene)), scene.size, boxes)


def test_separated_sideways_cards_on_textured_table(allow_synthetic_portraits):
    scene = textured_table((530, 960))
    boxes = []
    for row in range(3):
        x, y = 130, 160 + row * 220
        paste_rounded(scene, (x, y), (270, 170), row + 1)
        boxes.append((x, y, 270, 170))
    assert_bounds(CardMatcherAdapter.detect(encode(scene)), scene.size, boxes)


@pytest.mark.parametrize("size", [(536, 800), (680, 800)])
@pytest.mark.parametrize("require_person", [True, False])
def test_tight_portrait_is_not_replaced_by_small_clothing_rectangles(size, require_person):
    data = pytest.importorskip("skimage.data")
    portrait = Image.fromarray(data.astronaut()).resize(size)
    # Reproduce the case where the original detector has no geometric outline;
    # lower JPEG quality itself creates unrelated legacy contours in this photo.
    regions = CardMatcherAdapter.detect(encode(portrait, quality=92), require_person=require_person)
    assert len(regions) == 1
    assert regions[0].width * regions[0].height > 0.9


@pytest.mark.parametrize("size", [(1, 2400), (2400, 1), (2, 2400)])
def test_very_narrow_image_returns_empty_without_resize_error(size):
    assert CardMatcherAdapter.detect(encode(Image.new("RGB", size, "white"))) == []
