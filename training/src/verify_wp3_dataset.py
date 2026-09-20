"""Validate the WP3 pavement YOLO split (D20/D40 only).

Does not re-split. Expected counts come from the measured filename-hash
prepare (seed 42) recorded in reports/dataset_report.json:

    train 7380 / val 1581 / test 1582 images, 17160 boxes
    class 0 = D20, class 1 = D40

Usage:
    python -m src.verify_wp3_dataset --root data/processed/pavement
    python -m src.verify_wp3_dataset --root /content/drive/MyDrive/tariqmap/pavement --yaml config/pavement.yaml
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
SPLITS = ("train", "val", "test")
ALLOWED_CLASS_IDS = {0, 1}
CLASS_NAMES = {0: "D20", 1: "D40"}
FORBIDDEN_WP_CODES = ("D00", "D10", "D50", "D60", "D90")

# Measured after prepare_dataset.py (seed 42). Do not change the test set.
EXPECTED_COUNTS = {
    "train_images": 7380,
    "val_images": 1581,
    "test_images": 1582,
    "total_images": 10543,
    "total_boxes": 17160,
    "boxes_by_class": {"D20": 10616, "D40": 6544},
    "split_seed": 42,
    "split_fractions": "70:15:15",
}

CANDIDATE_ROOTS = (
    Path("data/processed/pavement"),
    Path("training/data/processed/pavement"),
    Path("/content/drive/MyDrive/tariqmap/pavement"),
    Path("/content/drive/MyDrive/Road-damage-project/training/data/processed/pavement"),
)


def locate_pavement_root(explicit: Path | None = None) -> Path | None:
    if explicit is not None:
        return explicit
    env = os.environ.get("WP3_PAVEMENT_ROOT")
    if env:
        return Path(env)
    for candidate in CANDIDATE_ROOTS:
        if _looks_like_pavement(candidate):
            return candidate.resolve()
    return None


def _looks_like_pavement(root: Path) -> bool:
    return (root / "images" / "train").is_dir() and (root / "labels" / "train").is_dir()


def _images(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(p for p in directory.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTENSIONS)


def write_colab_yaml(dataset_root: Path, dest: Path) -> Path:
    """Write a YOLO data YAML with an absolute path for Colab cwd."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(
        "# Auto-generated for Colab. WP3 pavement only. Do not re-split.\n"
        f"path: {dataset_root.resolve()}\n"
        "train: images/train\n"
        "val: images/val\n"
        "test: images/test\n"
        "names:\n"
        "  0: D20\n"
        "  1: D40\n"
    )
    return dest


def verify(
    root: Path,
    yaml_path: Path | None = None,
    check_expected_counts: bool = True,
) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    split_images: dict[str, int] = {}
    split_labels: dict[str, int] = {}
    box_ids: Counter = Counter()
    named_boxes: Counter = Counter()
    bad_lines = 0
    mismatched_pairs = 0

    if not root.exists():
        errors.append(
            f"WP3 pavement root not found: {root}. "
            "Images are gitignored. Upload/rsync training/data/processed/pavement "
            "or unzip pavement_wp3_splits.zip and set --root / WP3_PAVEMENT_ROOT."
        )
        return _report(root, yaml_path, errors, warnings, split_images, split_labels, box_ids, named_boxes, bad_lines)

    seen_stems: set[str] = set()
    for split in SPLITS:
        img_dir = root / "images" / split
        lbl_dir = root / "labels" / split
        images = _images(img_dir)
        labels = sorted(lbl_dir.glob("*.txt")) if lbl_dir.is_dir() else []
        split_images[split] = len(images)
        split_labels[split] = len(labels)
        if not images:
            errors.append(f"{split}: no images in {img_dir}")
        if not labels:
            errors.append(f"{split}: no labels in {lbl_dir}")
        img_stems = {p.stem for p in images}
        lbl_stems = {p.stem for p in labels}
        missing_lbl = sorted(img_stems - lbl_stems)
        missing_img = sorted(lbl_stems - img_stems)
        if missing_lbl:
            mismatched_pairs += len(missing_lbl)
            errors.append(f"{split}: {len(missing_lbl)} images missing labels (e.g. {missing_lbl[:3]})")
        if missing_img:
            mismatched_pairs += len(missing_img)
            errors.append(f"{split}: {len(missing_img)} labels missing images (e.g. {missing_img[:3]})")
        overlap = seen_stems & img_stems
        if overlap:
            errors.append(f"split leakage: {sorted(overlap)[:5]} appear in more than one split")
        seen_stems |= img_stems

        for label in labels:
            for line_no, line in enumerate(label.read_text().splitlines(), 1):
                if not line.strip():
                    continue
                parts = line.split()
                if len(parts) != 5:
                    bad_lines += 1
                    errors.append(f"{label}:{line_no}: expected 5 YOLO fields")
                    continue
                raw_cls, *coords = parts
                try:
                    cls = int(float(raw_cls))
                    vals = [float(c) for c in coords]
                except ValueError:
                    bad_lines += 1
                    errors.append(f"{label}:{line_no}: non-numeric fields")
                    continue
                if cls not in ALLOWED_CLASS_IDS:
                    errors.append(
                        f"{label}:{line_no}: class id {cls} is not WP3 (must be 0=D20 or 1=D40). "
                        "D00/D10/D50/D60/D90 must not appear in pavement labels."
                    )
                    continue
                if any(not 0.0 <= v <= 1.0 for v in vals):
                    errors.append(f"{label}:{line_no}: coordinate out of [0,1]: {vals}")
                    continue
                cx, cy, w, h = vals
                if w <= 0 or h <= 0:
                    errors.append(f"{label}:{line_no}: non-positive box {w}x{h}")
                    continue
                box_ids[cls] += 1
                named_boxes[CLASS_NAMES[cls]] += 1

    if yaml_path is not None:
        if not yaml_path.exists():
            errors.append(f"YAML not found: {yaml_path}")
        else:
            text = yaml_path.read_text()
            if "D20" not in text or "D40" not in text:
                errors.append(f"{yaml_path}: names must include D20 and D40")
            for code in FORBIDDEN_WP_CODES:
                # comments may mention other WPs; require names block not list them as keys
                pass
            try:
                import yaml  # type: ignore
                cfg = yaml.safe_load(text)
                names = cfg.get("names") or {}
                if isinstance(names, dict):
                    mapped = {int(k): str(v) for k, v in names.items()}
                elif isinstance(names, list):
                    mapped = {i: str(v) for i, v in enumerate(names)}
                else:
                    mapped = {}
                if mapped.get(0) != "D20" or mapped.get(1) != "D40":
                    errors.append(f"{yaml_path}: names must be 0:D20 1:D40, got {mapped}")
                extra = set(mapped.values()) - {"D20", "D40"}
                if extra:
                    errors.append(f"{yaml_path}: extra classes not allowed in WP3: {sorted(extra)}")
            except ImportError:
                warnings.append("PyYAML not installed; YAML names checked as text only")

    if check_expected_counts and not errors:
        for split, key in (("train", "train_images"), ("val", "val_images"), ("test", "test_images")):
            got = split_images.get(split, 0)
            expected = EXPECTED_COUNTS[key]
            if got != expected:
                errors.append(
                    f"{split} image count {got} != expected {expected}. "
                    "Do not re-split. Restore the seed-42 pavement folder."
                )
        total_boxes = int(sum(box_ids.values()))
        if total_boxes != EXPECTED_COUNTS["total_boxes"]:
            errors.append(
                f"box count {total_boxes} != expected {EXPECTED_COUNTS['total_boxes']}"
            )
        for name, expected in EXPECTED_COUNTS["boxes_by_class"].items():
            got = int(named_boxes.get(name, 0))
            if got != expected:
                errors.append(f"{name} boxes {got} != expected {expected}")

    if mismatched_pairs:
        warnings.append(f"image/label mismatches: {mismatched_pairs}")

    return _report(
        root, yaml_path, errors, warnings, split_images, split_labels,
        box_ids, named_boxes, bad_lines,
    )


def _report(
    root: Path,
    yaml_path: Path | None,
    errors: list[str],
    warnings: list[str],
    split_images: dict[str, int],
    split_labels: dict[str, int],
    box_ids: Counter,
    named_boxes: Counter,
    bad_lines: int,
) -> dict[str, Any]:
    ok = not errors
    return {
        "status": "OK" if ok else "FAIL",
        "verified_at_utc": datetime.now(timezone.utc).isoformat(),
        "root": str(root),
        "yaml": str(yaml_path) if yaml_path else None,
        "agent": "pavement",
        "wp": "WP3",
        "classes": {"0": "D20", "1": "D40"},
        "depth_estimation": False,
        "split_images": split_images,
        "split_labels": split_labels,
        "box_counts_by_id": {str(k): int(v) for k, v in sorted(box_ids.items())},
        "box_counts_by_name": dict(named_boxes),
        "total_boxes": int(sum(box_ids.values())),
        "bad_lines": bad_lines,
        "expected_counts": EXPECTED_COUNTS,
        "re_split": False,
        "errors": errors[:50],
        "error_count": len(errors),
        "warnings": warnings,
        "note": (
            "WP3 only. Do not mix D00/D10 (WP2) or D50/D60/D90 (WP4). "
            "Do not re-run prepare_dataset.py on this folder."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify WP3 pavement YOLO split")
    parser.add_argument("--root", type=Path, default=None)
    parser.add_argument("--yaml", type=Path, default=None)
    parser.add_argument(
        "--skip-expected-counts",
        action="store_true",
        help="Do not require 7380/1581/1582 (for unit fixtures only)",
    )
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument(
        "--write-colab-yaml",
        type=Path,
        default=None,
        help="Write a YOLO YAML with an absolute dataset path",
    )
    args = parser.parse_args()
    root = args.root or locate_pavement_root()
    if root is None:
        report = {
            "status": "FAIL",
            "errors": [
                "Could not locate training/data/processed/pavement. "
                "Images are gitignored. Provide --root or WP3_PAVEMENT_ROOT."
            ],
            "expected_counts": EXPECTED_COUNTS,
        }
        print(json.dumps(report, indent=2))
        sys.exit(2)
    yaml_path = args.yaml
    if yaml_path is None:
        guess = Path(__file__).resolve().parents[1] / "config" / "pavement.yaml"
        yaml_path = guess if guess.exists() else None
    report = verify(root, yaml_path, check_expected_counts=not args.skip_expected_counts)
    if args.write_colab_yaml:
        write_colab_yaml(root, args.write_colab_yaml)
        report["colab_yaml"] = str(args.write_colab_yaml)
    text = json.dumps(report, indent=2)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
    if report["status"] != "OK":
        sys.exit(1)


if __name__ == "__main__":
    main()
