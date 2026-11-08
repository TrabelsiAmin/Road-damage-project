#!/usr/bin/env python3
"""Source contract for the default Android model. Does not load weights.

Fails if the legacy runner stops using stretch, starts letterboxing, or if the
RoadSense shape gate is loosened. Run from the repo root or any cwd.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER = ROOT / "app/lib/services/tflite_agent_runner.dart"
PRE = ROOT / "app/lib/inference/preprocessing.dart"
ROAD = ROOT / "app/lib/services/roadsense_agent_runner.dart"
DEC = ROOT / "app/lib/inference/legacy_decoder.dart"
TEST_IMAGES = ROOT / "test_images.py"
CONST = ROOT / "app/lib/core/constants.dart"


def main() -> int:
    runner = RUNNER.read_text(encoding="utf-8")
    pre = PRE.read_text(encoding="utf-8")
    road = ROAD.read_text(encoding="utf-8")
    dec = DEC.read_text(encoding="utf-8")
    images = TEST_IMAGES.read_text(encoding="utf-8")
    const = CONST.read_text(encoding="utf-8")
    errors: list[str] = []

    def need(cond: bool, msg: str) -> None:
        if not cond:
            errors.append(msg)

    need("stretchToModelInput(decoded, inputSize: inputSize)" in runner, "legacy runner must call stretchToModelInput")
    need("letterboxProcess" not in runner, "legacy runner must not letterbox")
    need("img.copyResize(decoded, width: inputSize, height: inputSize)" not in runner, "stretch must live in stretchToModelInput, not be inlined again")
    need("decodeLegacyYoloOutput(" in runner, "legacy runner must use decodeLegacyYoloOutput")
    need("isLegacyRoadDamageOutputShape" in runner, "legacy load must gate on [1, 8, 8400]")
    need("img.Image stretchToModelInput" in pre, "stretchToModelInput must exist")
    need("return img.copyResize(source, width: inputSize, height: inputSize);" in pre, "stretch must be a plain copyResize")
    need("letterboxProcess(decoded, inputSize: inputSize)" in road, "RoadSense must letterbox")
    need("[1, 9, 8400]" in road, "RoadSense must require [1, 9, 8400]")
    need("[1, 3, 640, 640]" in road or "inShape[1] != 3" in road, "RoadSense must require NCHW")
    need("shape[1] == 8" in dec and "shape[2] == 8400" in dec, "legacy shape helper must demand 8x8400")
    need("output[0][4 + c][anchor]" in dec, "scores must be channel-major")
    need("'D40': 0.40" in runner, "D40 threshold must stay 0.40")
    need("'D20': 0.30" in runner, "D20 threshold must stay 0.30")
    need("UNPROVEN" in images, "test_images.py must keep the unproven-names warning")
    need("['Crack', 'Pothole', 'Rutting', 'Uneven-Surface']" in images, "script display strings must not be silently renamed")
    need("defaultValue: false" in const and "useRoadSenseModel" in const, "RoadSense must stay off by default")
    need("0: 'D00'" in runner and "3: 'D40'" in runner, "Flutter class contract must stay D00..D40")

    if errors:
        print("CONTRACT FAILED")
        for e in errors:
            print(" -", e)
        return 1
    print("CONTRACT OK", ROOT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
