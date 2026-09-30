"""Inspect a labeled YOLO dataset. Never invent class counts.

Reports class names, annotation format, splits, class distribution,
image sizes, bounding-box stats, and small-object rates.

Usage:
    python -m src.analyze_labeled_dataset --dataset data/raw/rdd_yolo --output reports/rdd_analysis.json
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

UNIFIED_NAMES = {
    0: "D00",
    1: "D10",
    2: "D20",
    3: "D40",
    4: "D50",
    5: "D60",
    6: "D90",
}

# COCO-style small object: area < 32² pixels
SMALL_PIXEL_AREA = 32 * 32


def _images(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*") if p.suffix.lower() in IMAGE_EXTENSIONS)


def _index_images(root: Path) -> dict[str, Path]:
    index: dict[str, Path] = {}
    for path in _images(root):
        index.setdefault(path.stem, path)
    return index


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


def analyze(dataset: Path) -> dict[str, Any]:
    if not dataset.exists():
        raise SystemExit(f"Dataset not found: {dataset}")

    xmls = list(dataset.rglob("*.xml"))
    txts = [p for p in dataset.rglob("*.txt") if p.name != "classes.txt"]
    images = _images(dataset)

    annotation_format = "none"
    if xmls and txts:
        annotation_format = "mixed_voc_and_yolo"
    elif xmls:
        annotation_format = "pascal_voc_xml"
    elif txts:
        annotation_format = "yolo_txt"

    splits_present = {
        name: (dataset / "images" / name).exists() or (dataset / name).exists()
        for name in ("train", "val", "test")
    }

    class_boxes: Counter = Counter()
    areas: list[float] = []
    pixel_areas: list[float] = []
    widths: list[int] = []
    heights: list[int] = []
    small_by_class: Counter = Counter()
    bad_lines = 0
    labeled_images = 0

    labels_dir = dataset / "labels" if (dataset / "labels").exists() else dataset
    images_dir = dataset / "images" if (dataset / "images").exists() else dataset
    image_index = _index_images(images_dir)

    for label in sorted(labels_dir.rglob("*.txt")):
        if label.name in {"classes.txt", "conversion_summary.json"}:
            continue
        lines = [ln for ln in label.read_text().splitlines() if ln.strip()]
        if not lines:
            continue
        labeled_images += 1
        img = image_index.get(label.stem)
        size = _probe_size(img) if img else None
        if size:
            widths.append(size[0])
            heights.append(size[1])
        for line in lines:
            parts = line.split()
            if len(parts) != 5:
                bad_lines += 1
                continue
            try:
                cls = int(float(parts[0]))
                _, _, w, h = (float(v) for v in parts[1:])
            except ValueError:
                bad_lines += 1
                continue
            name = UNIFIED_NAMES.get(cls, f"class_{cls}")
            class_boxes[name] += 1
            areas.append(w * h)
            if size:
                px = w * size[0] * h * size[1]
                pixel_areas.append(px)
                if px < SMALL_PIXEL_AREA:
                    small_by_class[name] += 1

    present = set(class_boxes)
    missing = [c for c in UNIFIED_NAMES.values() if c not in present]

    def _pct(n: int, d: int) -> float:
        return round(100.0 * n / d, 2) if d else 0.0

    report: dict[str, Any] = {
        "dataset": str(dataset.resolve()),
        "image_count": len(images),
        "labeled_label_files": labeled_images,
        "annotation_format": annotation_format,
        "xml_count": len(xmls),
        "yolo_txt_count": len(txts),
        "splits_present": splits_present,
        "class_distribution": dict(class_boxes),
        "missing_classes": missing,
        "d90_status": "ABSENT" if "D90" not in present else "PRESENT",
        "d50_status": "PRESENT" if "D50" in present else "ABSENT_OR_UNMAPPED",
        "d60_status": "PRESENT" if "D60" in present else "ABSENT_OR_UNMAPPED",
        "bad_label_lines": bad_lines,
        "bbox_normalized_area": {
            "count": len(areas),
            "min": round(min(areas), 6) if areas else None,
            "max": round(max(areas), 6) if areas else None,
            "mean": round(sum(areas) / len(areas), 6) if areas else None,
        },
        "image_sizes": {
            "sampled": len(widths),
            "width_min": min(widths) if widths else None,
            "width_max": max(widths) if widths else None,
            "height_min": min(heights) if heights else None,
            "height_max": max(heights) if heights else None,
        },
        "small_objects_area_lt_32px": {
            "by_class": dict(small_by_class),
            "total": int(sum(small_by_class.values())),
            "percent_of_boxes": _pct(int(sum(small_by_class.values())), len(pixel_areas)),
        },
        "verdict": (
            "LABELED — suitable for prepare_dataset.py / train.py"
            if class_boxes and annotation_format != "none"
            else "STOP — no usable labels. Do not train. "
            "Do not use Global_Potholes_Dataset-image."
        ),
    }
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()
    report = analyze(args.dataset)
    text = json.dumps(report, indent=2)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)


if __name__ == "__main__":
    main()
