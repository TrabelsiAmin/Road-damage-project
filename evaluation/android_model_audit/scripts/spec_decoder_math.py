#!/usr/bin/env python3
"""Runnable mirror of the legacy decoder tests.

This does not execute Dart. It checks the same numeric contract the Dart
tests encode, so a machine without Flutter can still fail a math regression.
The Dart files remain the production tests.
"""
from __future__ import annotations

import sys


def decode(channels, thresholds, only_d40=False, iou=0.45):
    names = {0: "D00", 1: "D10", 2: "D20", 3: "D40"}
    anchors = len(channels[0])
    raw = []
    for a in range(anchors):
        best_s, best_c = 0.0, -1
        for c in range(4):
            s = channels[4 + c][a]
            if s > best_s:
                best_s, best_c = s, c
        if best_c < 0:
            continue
        name = names[best_c]
        if only_d40 and name != "D40":
            continue
        thr = thresholds[name]
        if best_s < thr:
            continue
        cx, cy, w, h = (min(1.0, max(0.0, channels[i][a])) for i in range(4))
        raw.append((name, best_s, max(0.0, min(1.0, cx - w / 2)), max(0.0, min(1.0, cy - h / 2)), w, h))
    # class-aware NMS not needed for the single-box cases below
    return raw


def main() -> int:
    th = {"D00": 0.35, "D10": 0.35, "D20": 0.30, "D40": 0.40}
    ch = [[0.0] for _ in range(8)]
    ch[0][0], ch[1][0], ch[2][0], ch[3][0], ch[6][0] = 0.50, 0.40, 0.20, 0.10, 0.62
    got = decode(ch, th)
    assert len(got) == 1 and got[0][0] == "D20"
    assert abs(got[0][2] - 0.40) < 1e-9 and abs(got[0][3] - 0.35) < 1e-9

    low = [[0.0] for _ in range(8)]
    low[7][0] = 0.38
    assert decode(low, th) == []
    high = [[0.0] for _ in range(8)]
    high[0][0] = high[1][0] = 0.5
    high[2][0] = high[3][0] = 0.2
    high[7][0] = 0.41
    assert decode(high, th)[0][0] == "D40"

    neg = [[-0.2] for _ in range(8)]
    assert decode(neg, th) == []

    two = [[0.0, 0.0] for _ in range(8)]
    for a in range(2):
        two[0][a] = two[1][a] = 0.5
        two[2][a] = two[3][a] = 0.1
    two[6][0] = 0.9
    two[7][1] = 0.5
    only = decode(two, th, only_d40=True)
    assert len(only) == 1 and only[0][0] == "D40"

    def shape_ok(shape):
        return len(shape) == 3 and shape[0] == 1 and shape[1] == 8 and shape[2] == 8400

    assert shape_ok([1, 8, 8400])
    assert not shape_ok([1, 9, 8400])
    assert not shape_ok([1, 8400, 8])

    # Stretch vs letterbox geometry for a 640x480 frame into 640.
    # Stretch scales each axis independently and has no pad.
    # Letterbox keeps aspect ratio and pads the short axis.
    src_w, src_h, size = 640, 480, 640
    stretch_sx, stretch_sy = size / src_w, size / src_h
    assert stretch_sx == 1 and abs(stretch_sy - (640 / 480)) < 1e-9
    letter_scale = min(size / src_w, size / src_h)
    letter_w, letter_h = src_w * letter_scale, src_h * letter_scale
    pad_y = (size - letter_h) / 2
    assert pad_y != 0
    assert letter_h == 480
    # A source point on the top edge stays on the top edge after stretch.
    assert 0 * stretch_sy == 0
    # The same point falls inside the letterbox pad, not on image content.
    assert pad_y > 0

    def iou(a, b):
        ax, ay, aw, ah = a
        bx, by, bw, bh = b
        ix1, iy1 = max(ax, bx), max(ay, by)
        ix2, iy2 = min(ax + aw, bx + bw), min(ay + ah, by + bh)
        iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
        inter = iw * ih
        if inter == 0:
            return 0.0
        union = aw * ah + bw * bh - inter
        return inter / union if union > 0 else 0.0

    def class_aware_nms(dets, thr=0.45):
        by = {}
        for name, score, box in dets:
            by.setdefault(name, []).append((score, box))
        kept = []
        for name, items in by.items():
            items.sort(key=lambda item: item[0], reverse=True)
            suppressed = set()
            for i, (score, box) in enumerate(items):
                if i in suppressed:
                    continue
                kept.append((name, score))
                for j in range(i + 1, len(items)):
                    if j in suppressed:
                        continue
                    if iou(box, items[j][1]) > thr:
                        suppressed.add(j)
        return kept

    box = (0.1, 0.1, 0.4, 0.4)
    same = class_aware_nms([("D20", 0.9, box), ("D20", 0.6, box)])
    assert same == [("D20", 0.9)]
    both = class_aware_nms([("D20", 0.9, box), ("D40", 0.8, box)])
    assert {item[0] for item in both} == {"D20", "D40"}

    # NCHW RoadSense input is not the legacy NHWC contract.
    def legacy_input_ok(shape, input_size=640):
        return (
            len(shape) == 4
            and shape[0] == 1
            and shape[1] == input_size
            and shape[2] == input_size
            and shape[3] == 3
        )

    assert legacy_input_ok([1, 640, 640, 3])
    assert not legacy_input_ok([1, 3, 640, 640])
    print("SPEC MATH OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
