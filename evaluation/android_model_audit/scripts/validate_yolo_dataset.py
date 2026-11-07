#!/usr/bin/env python3
"""Validate a YOLO dataset without moving or deleting any file.

Writes a JSON report to --out. If labels are missing, the report says so and
exits 2. It never creates label files and never rewrites images.

Example:
  python3 evaluation/android_model_audit/scripts/validate_yolo_dataset.py \\
      --images Global_Potholes_Dataset-image/images \\
      --labels Global_Potholes_Dataset-image/labels \\
      --out evaluation/android_model_audit/label_validation.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--images", type=Path, required=True)
    ap.add_argument("--labels", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--nc", type=int, default=4, help="expected class-id upper bound (exclusive)")
    args = ap.parse_args()

    report: dict = {
        "images_dir": str(args.images),
        "labels_dir": str(args.labels),
        "status": "NOT VERIFIED",
    }
    if not args.images.is_dir():
        report["status"] = "BLOCKED"
        report["reason"] = "images directory does not exist"
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 2

    images = sorted(p for p in args.images.iterdir() if p.suffix.lower() in IMAGE_EXT and p.is_file())
    report["image_count"] = len(images)
    if not args.labels.is_dir():
        report["status"] = "BLOCKED"
        report["reason"] = "labels directory does not exist; no boxes to validate"
        report["label_file_count"] = 0
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 2

    label_files = sorted(p for p in args.labels.iterdir() if p.suffix.lower() == ".txt" and p.is_file())
    report["label_file_count"] = len(label_files)
    missing = []
    empty = []
    invalid_rows = []
    class_counts = {str(i): 0 for i in range(args.nc)}
    unknown_class = 0
    boxes = 0
    by_stem = {p.stem: p for p in label_files}
    for img in images:
        lab = by_stem.get(img.stem)
        if lab is None:
            missing.append(img.name)
            continue
        text = lab.read_text(encoding="utf-8", errors="replace").strip()
        if not text:
            empty.append(img.name)
            continue
        for line_no, line in enumerate(text.splitlines(), start=1):
            parts = line.split()
            if len(parts) != 5:
                invalid_rows.append({"file": lab.name, "line": line_no, "reason": "not 5 fields"})
                continue
            try:
                cid = int(parts[0])
                x, y, w, h = (float(v) for v in parts[1:])
            except ValueError:
                invalid_rows.append({"file": lab.name, "line": line_no, "reason": "non-numeric"})
                continue
            if cid < 0 or cid >= args.nc:
                unknown_class += 1
                invalid_rows.append({"file": lab.name, "line": line_no, "reason": f"class {cid} outside 0..{args.nc - 1}"})
            else:
                class_counts[str(cid)] += 1
            if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0 and 0.0 < w <= 1.0 and 0.0 < h <= 1.0):
                invalid_rows.append({"file": lab.name, "line": line_no, "reason": "box outside normalized range"})
            if x - w / 2 < -1e-6 or y - h / 2 < -1e-6 or x + w / 2 > 1 + 1e-6 or y + h / 2 > 1 + 1e-6:
                invalid_rows.append({"file": lab.name, "line": line_no, "reason": "box extends outside the image"})
            boxes += 1

    extra_labels = [p.name for p in label_files if not any(img.stem == p.stem for img in images)]
    report.update({
        "status": "VERIFIED" if images and not missing and not invalid_rows else "PARTIALLY VERIFIED",
        "box_count": boxes,
        "images_missing_labels": len(missing),
        "empty_label_files": len(empty),
        "invalid_row_count": len(invalid_rows),
        "unknown_class_rows": unknown_class,
        "extra_label_files": len(extra_labels),
        "class_counts": class_counts,
        "missing_label_sample": missing[:20],
        "invalid_row_sample": invalid_rows[:20],
    })
    if not label_files:
        report["status"] = "BLOCKED"
        report["reason"] = "labels directory has zero txt files"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2))
    print(json.dumps({k: report[k] for k in ("status", "image_count", "label_file_count", "box_count", "invalid_row_count")}, indent=2))
    return 0 if report["status"] == "VERIFIED" else 2


if __name__ == "__main__":
    sys.exit(main())
