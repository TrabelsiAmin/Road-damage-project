"""WP3 small-object bins from YOLO labels (and optional predictions).

Bins are characteristic box size sqrt(w_px * h_px):
    <32 px, 32–64 px, >64 px
computed per class D20 (id 0) and D40 (id 1).

Works without Ultralytics. If image sizes cannot be read, status is
NOT_AVAILABLE for pixel bins (normalized-area bins are still reported).

Usage:
    python -m src.eval_small_objects --root data/processed/pavement --split test \\
        --output reports/wp3/baseline/small_objects.json
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
CLASS_NAMES = {0: "D20", 1: "D40"}
BINS = (
    ("lt_32", 0.0, 32.0),
    ("32_64", 32.0, 64.0),
    ("gt_64", 64.0, float("inf")),
)


def _probe_size(path: Path) -> tuple[int, int] | None:
    try:
        from PIL import Image
    except ImportError:
        return None
    try:
        with Image.open(path) as im:
            return im.width, im.height
    except OSError:
        return None


def _find_image(images_dir: Path, stem: str) -> Path | None:
    for ext in IMAGE_EXTENSIONS:
        candidate = images_dir / f"{stem}{ext}"
        if candidate.exists():
            return candidate
    return None


def _bin_name(size_px: float) -> str:
    for name, lo, hi in BINS:
        if lo <= size_px < hi:
            return name
    return "gt_64"


def analyze_split(root: Path, split: str) -> dict[str, Any]:
    labels_dir = root / "labels" / split
    images_dir = root / "images" / split
    per_class: dict[str, dict[str, int]] = {
        name: {b[0]: 0 for b in BINS} | {"total": 0, "unbinned_no_size": 0}
        for name in CLASS_NAMES.values()
    }
    pixel_sizes: list[float] = []
    missing_images = 0
    bad_lines = 0
    boxes = 0

    if not labels_dir.is_dir():
        return {
            "status": "NOT_AVAILABLE",
            "reason": f"labels split missing: {labels_dir}",
            "split": split,
            "per_class": per_class,
        }

    label_files = sorted(labels_dir.glob("*.txt"))
    size_cache: dict[str, tuple[int, int] | None] = {}
    for label in label_files:
        img = _find_image(images_dir, label.stem)
        if img is None:
            missing_images += 1
            size = None
        else:
            if label.stem not in size_cache:
                size_cache[label.stem] = _probe_size(img)
            size = size_cache[label.stem]
        for line in label.read_text().splitlines():
            if not line.strip():
                continue
            parts = line.split()
            if len(parts) != 5:
                bad_lines += 1
                continue
            try:
                cls = int(float(parts[0]))
                _, _, nw, nh = (float(x) for x in parts[1:])
            except ValueError:
                bad_lines += 1
                continue
            name = CLASS_NAMES.get(cls)
            if name is None:
                continue
            boxes += 1
            per_class[name]["total"] += 1
            if size is None:
                per_class[name]["unbinned_no_size"] += 1
                continue
            w_px = nw * size[0]
            h_px = nh * size[1]
            char = (max(w_px, 0.0) * max(h_px, 0.0)) ** 0.5
            pixel_sizes.append(char)
            per_class[name][_bin_name(char)] += 1

    status = "OK" if boxes else "NOT_AVAILABLE"
    reason = None
    if not boxes:
        reason = f"No WP3 boxes under {labels_dir}"
    elif all(v["unbinned_no_size"] == v["total"] for v in per_class.values()):
        status = "NOT_AVAILABLE"
        reason = "Pillow/image sizes unavailable; cannot assign pixel bins"

    return {
        "status": status,
        "reason": reason,
        "split": split,
        "label_files": len(label_files),
        "boxes": boxes,
        "missing_images": missing_images,
        "bad_lines": bad_lines,
        "bin_definition": "sqrt(w_px * h_px); lt_32 / 32_64 / gt_64",
        "per_class": per_class,
        "size_px": {
            "count": len(pixel_sizes),
            "min": round(min(pixel_sizes), 3) if pixel_sizes else None,
            "max": round(max(pixel_sizes), 3) if pixel_sizes else None,
            "mean": round(sum(pixel_sizes) / len(pixel_sizes), 3) if pixel_sizes else None,
        },
    }


def analyze_root(root: Path, split: str | None = None) -> dict[str, Any]:
    splits = (split,) if split else ("train", "val", "test")
    by_split = {s: analyze_split(root, s) for s in splits}
    return {
        "wp": "WP3",
        "agent": "pavement",
        "analyzed_at_utc": datetime.now(timezone.utc).isoformat(),
        "root": str(root),
        "model_metrics": None,
        "note": (
            "These bins are ground-truth box sizes, not detector recall. "
            "Model small-object AP is NOT_RUN until eval_wp3 writes status OK."
        ),
        "splits": by_split,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="WP3 small-object size bins")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--split", default=None, choices=("train", "val", "test"))
    parser.add_argument("--output", type=Path, default=Path("reports/wp3/small_objects.json"))
    args = parser.parse_args()
    if not args.root.exists():
        report = {
            "status": "NOT_AVAILABLE",
            "reason": f"dataset root missing: {args.root}",
            "model_metrics": None,
        }
    else:
        report = analyze_root(args.root, args.split)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
