"""Portrait robustness without reducing the evidence required for acceptance."""

import numpy as np
import pytest
from PIL import Image, ImageEnhance

from app.integrations.card_matcher.portrait_detector import PortraitDetector


@pytest.mark.parametrize(
    ("angle", "brightness", "contrast"),
    [(-35, 1.0, 0.3), (25, 0.3, 0.3), (35, 0.3, 0.3)],
)
def test_low_contrast_tilted_portraits_survive_normalization(angle, brightness, contrast):
    data = pytest.importorskip("skimage.data")
    portrait = Image.fromarray(data.astronaut()).crop((110, 20, 370, 395)).resize((230, 332))
    portrait = portrait.rotate(angle, fillcolor="#eee8f5")
    portrait = ImageEnhance.Contrast(portrait).enhance(contrast)
    portrait = ImageEnhance.Brightness(portrait).enhance(brightness)
    assert PortraitDetector().contains_person(portrait)


@pytest.mark.parametrize("name", ["brick", "grass", "coins", "coffee", "checkerboard"])
def test_real_non_portrait_textures_still_fail(name):
    data = pytest.importorskip("skimage.data")
    assert not PortraitDetector().contains_person(Image.fromarray(getattr(data, name)()))


class EvidenceNetwork:
    def __init__(self, mode):
        self.mode = mode
        self.calls = 0

    def setInputSize(self, size):
        pass

    def detect(self, image):
        self.calls += 1
        if self.mode == "none":
            return 0, None
        face = np.zeros((1, 15), dtype=np.float32)
        face[0, :4] = [40, 40, 60, 70]
        face[0, -1] = 0.8
        if self.mode == "padding" and self.calls > 4:
            # A confident response in the artificial border must not validate
            # a real crop. Its apparent visibility in the canvas is irrelevant.
            face[0, :4] = [0, 0, 64, 64]
            face[0, -1] = 0.99
        return 1, face


@pytest.mark.parametrize(("mode", "calls"), [("none", 4), ("weak", 12), ("padding", 12)])
def test_retries_are_bounded_and_never_accept_weak_or_padding_evidence(mode, calls):
    detector = object.__new__(PortraitDetector)
    detector.network = EvidenceNetwork(mode)
    assert not detector.contains_person(Image.new("RGB", (230, 332), "#eeeeee"))
    assert detector.network.calls == calls
