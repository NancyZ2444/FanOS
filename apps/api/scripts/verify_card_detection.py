"""Evaluate detection only against manually labelled photo boxes; no DB or matching.

Manifest: {"cases": [{"file": "photo.jpg", "boxes": [[x, y, width, height], ...]}]}.
Boxes are normalized to the EXIF-oriented original image. Unlabelled fragments
at the photograph edge are intentionally not counted as complete cards.
Optional "polygons" contains one four-corner [[x, y], ...] list per labelled
box. These enforce separate extra-background, missing-card and corner-error
limits; the reported count/box IoU alone does not validate a tight crop.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.integrations.card_matcher.adapter import CardMatcherAdapter  # noqa: E402


def overlap(a: list[float], b: list[float]) -> float:
    intersection = max(0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])) * max(
        0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
    )
    return intersection / max(1e-9, a[2] * a[3] + b[2] * b[3] - intersection)


def matched_assignment(expected_boxes, observed, minimum_iou):
    # One-to-one maximum-cardinality assignment prevents a merged outer
    # frame or duplicate crop from satisfying several labelled cards.
    edges = [
        sorted(
            (j for j, box in enumerate(observed) if overlap(expected, box) >= minimum_iou),
            key=lambda j: -overlap(expected, observed[j]),
        )
        for expected in expected_boxes
    ]
    assigned: dict[int, int] = {}

    def assign(i: int, visited: set[int]) -> bool:
        for j in edges[i]:
            if j in visited:
                continue
            visited.add(j)
            if j not in assigned or assign(assigned[j], visited):
                assigned[j] = i
                return True
        return False

    for i in range(len(edges)):
        assign(i, set())
    return assigned


def boundary_metrics(expected, observed, image_size):
    """Measure both extra background and missing card area, independently of count."""
    expected = np.float32(expected) * np.float32(image_size)
    observed = np.float32([[p["x"], p["y"]] for p in observed]) * np.float32(image_size)
    expected_area, observed_area = abs(cv2.contourArea(expected)), abs(cv2.contourArea(observed))
    intersection = cv2.intersectConvexConvex(expected, observed)[0]
    short_side = float(min(np.linalg.norm(np.roll(expected, -1, axis=0) - expected, axis=1)))
    # Corner ordering may start at a different physical corner after rotation.
    error = (
        min(
            float(np.linalg.norm(expected - np.roll(observed, offset, axis=0), axis=1).max())
            for offset in range(4)
        )
        / short_side
    )
    return {
        "outside_fraction": max(0, 1 - intersection / observed_area),
        "missing_fraction": max(0, 1 - intersection / expected_area),
        "maximum_corner_error": error,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--images", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--minimum-iou", type=float, default=0.7)
    args = parser.parse_args()
    cases = json.loads(args.manifest.read_text())["cases"]
    args.output.mkdir(parents=True, exist_ok=True)
    report = {"minimum_iou": args.minimum_iou, "cases": [], "passed": True}
    panels = []
    for number, case in enumerate(cases, 1):
        path = args.images / case["file"]
        content = path.read_bytes()
        started = time.perf_counter()
        regions = CardMatcherAdapter.detect(content)
        elapsed = time.perf_counter() - started
        observed = [[r.x, r.y, r.width, r.height] for r in regions]
        assigned = matched_assignment(case["boxes"], observed, args.minimum_iou)
        matched = len(assigned)
        passed = matched == len(case["boxes"]) == len(regions)
        original = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
        boundaries = []
        if "polygons" in case:
            for j, i in sorted(assigned.items()):
                corners = regions[j].payload().get("corners")
                if corners is None:
                    passed = False
                    boundaries.append({"number": j + 1, "passed": False})
                    continue
                metrics = boundary_metrics(case["polygons"][i], corners, original.size)
                boundary_passed = (
                    metrics["outside_fraction"] <= case.get("maximum_outside", 0.03)
                    and metrics["missing_fraction"] <= case.get("maximum_missing", 0.02)
                    and metrics["maximum_corner_error"] <= case.get("maximum_corner_error", 0.03)
                )
                passed &= boundary_passed
                boundaries.append(
                    {
                        "number": j + 1,
                        "passed": boundary_passed,
                        **{key: round(value, 5) for key, value in metrics.items()},
                    }
                )
        row = {
            "file": case["file"],
            "sha256": hashlib.sha256(content).hexdigest(),
            "expected": len(case["boxes"]),
            "detected": len(regions),
            "matched_boxes": matched,
            "seconds": round(elapsed, 3),
            "passed": passed,
            "regions": [r.payload() for r in regions],
            "boundary_metrics": boundaries,
            "matched_ious": [
                round(overlap(case["boxes"][i], observed[j]), 3)
                for j, i in sorted(assigned.items())
            ],
        }
        report["cases"].append(row)
        report["passed"] &= passed
        draw = ImageDraw.Draw(original)
        for i, region in enumerate(regions, 1):
            x, y, w, h = observed[i - 1]
            corners = region.payload().get("corners")
            polygon = (
                [(p["x"] * original.width, p["y"] * original.height) for p in corners]
                if corners
                else [
                    (x * original.width, y * original.height),
                    ((x + w) * original.width, y * original.height),
                    ((x + w) * original.width, (y + h) * original.height),
                    (x * original.width, (y + h) * original.height),
                ]
            )
            draw.line(polygon + [polygon[0]], fill="#00d876", width=max(3, original.width // 250))
            region.crop.save(args.output / f"{number:02d}-crop-{i:02d}.jpg", quality=95)
        original.save(args.output / f"{number:02d}-detected.jpg", quality=95)
        thumbnail = ImageOps.contain(original, (500, 500))
        panel = Image.new("RGB", (520, 550), "white")
        panel.paste(thumbnail, ((520 - thumbnail.width) // 2, 10))
        ImageDraw.Draw(panel).text(
            (10, 520),
            f"{number:02d}: {len(regions)}/{len(case['boxes'])}; "
            f"location {matched}/{len(case['boxes'])}",
            fill="black",
        )
        panels.append(panel)
        print(json.dumps(row, ensure_ascii=False), flush=True)
    sheet = Image.new("RGB", (520 * min(4, len(panels)), 550 * ((len(panels) + 3) // 4)), "#ddd")
    for i, panel in enumerate(panels):
        sheet.paste(panel, ((i % 4) * 520, (i // 4) * 550))
    sheet.save(args.output / "contact-sheet.jpg", quality=95)
    (args.output / "report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    )
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
