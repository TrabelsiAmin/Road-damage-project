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

EXPECTED_REPO_FILES = (
    "training/config/pavement.yaml",
    "training/reports/dataset_report.json",
    "training/reports/METRICS.md",
    "training/src/verify_wp3_dataset.py",
    "training/src/eval_wp3.py",
    "training/src/eval_small_objects.py",
    "training/evaluation/compare_wp3_models.py",
    "training/colab/WP3_YOLOv8_training.ipynb",
    "docs/wp3-training.md",
)

DATA_RECOVERY_INSTRUCTIONS = (
    "Prepared WP3 JPEGs are missing (training/data/ is gitignored). "
    "Do NOT wget the 13.3GB RDD2022 zip by default. Recover data with one of: "
    "(1) Google Drive: mount Drive and unzip pavement_wp3_splits.zip "
    "(processed pavement splits only) or set WP3_PAVEMENT_ROOT to that folder; "
    "(2) If an RDD extract is already on disk, run "
    "`python -m src.convert_rdd_voc --source <RDD_EXTRACT> --output data/rdd_yolo` "
    "then `python -m src.prepare_dataset --source data/rdd_yolo "
    "--output data/processed --class-map config/source-class-map.json --seed 42` "
    "and point --root at data/processed/pavement. "
    "Never auto-download RDD2022_released_through_CRDDC2022.zip in this notebook."
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
    """Write a YOLO data YAML with an absolute path for Colab cwd.

    Names and split keys are copied from training/config/pavement.yaml
    (0: D20, 1: D40). Only `path` is rewritten to the absolute dataset root.
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(
        "# Auto-generated for Colab from training/config/pavement.yaml.\n"
        "# WP3 pavement only. Do not re-split. Do not invent class names.\n"
        f"path: {dataset_root.resolve()}\n"
        "train: images/train\n"
        "val: images/val\n"
        "test: images/test\n"
        "names:\n"
        "  0: D20\n"
        "  1: D40\n"
    )
    return dest


def check_wp3_repo(repo_root: Path) -> dict[str, Any]:
    """Fail clearly if WP3 config/docs/scripts are missing. Splits may be gitignored."""
    errors: list[str] = []
    present: list[str] = []
    yaml_names: dict[str, str] | None = None
    yaml_path = repo_root / "training" / "config" / "pavement.yaml"
    if not (repo_root / "training" / "config" / "pavement.yaml").exists():
        # Allow being called with the training/ directory as root.
        alt = repo_root / "config" / "pavement.yaml"
        if alt.exists():
            repo_root = repo_root.parent
            yaml_path = repo_root / "training" / "config" / "pavement.yaml"

    for rel in EXPECTED_REPO_FILES:
        path = repo_root / rel
        if path.is_file():
            present.append(rel)
        else:
            errors.append(f"missing expected WP3 file: {rel}")

    if yaml_path.is_file():
        text = yaml_path.read_text()
        try:
            import yaml  # type: ignore

            cfg = yaml.safe_load(text) or {}
            names = cfg.get("names") or {}
            if isinstance(names, dict):
                yaml_names = {str(k): str(v) for k, v in names.items()}
            elif isinstance(names, list):
                yaml_names = {str(i): str(v) for i, v in enumerate(names)}
            mapped = {}
            if isinstance(names, dict):
                mapped = {int(k): str(v) for k, v in names.items()}
            elif isinstance(names, list):
                mapped = {i: str(v) for i, v in enumerate(names)}
            if mapped.get(0) != "D20" or mapped.get(1) != "D40":
                errors.append(f"{yaml_path}: names must be 0:D20 1:D40, got {mapped}")
            extra = set(mapped.values()) - {"D20", "D40"}
            if extra:
                errors.append(f"{yaml_path}: extra classes not allowed in WP3: {sorted(extra)}")
            for code in FORBIDDEN_WP_CODES:
                if code in list(mapped.values()):
                    errors.append(f"{yaml_path}: WP2/WP4 class {code} must not be in pavement.yaml names")
        except ImportError:
            if "0: D20" not in text or "1: D40" not in text:
                errors.append(f"{yaml_path}: names must include 0: D20 and 1: D40")

    processed = repo_root / "training" / "data" / "processed" / "pavement"
    processed_state = {
        "path": str(processed),
        "exists": processed.exists(),
        "labels_train": (
            len(list((processed / "labels" / "train").glob("*.txt")))
            if (processed / "labels" / "train").is_dir()
            else 0
        ),
        "images_train": len(_images(processed / "images" / "train")),
        "note": (
            "Processed splits live under training/data/ which is gitignored. "
            "A missing folder on Colab is expected until Drive unzip or local convert."
        ),
    }

    return {
        "status": "OK" if not errors else "FAIL",
        "repo_root": str(repo_root),
        "present": present,
        "errors": errors,
        "yaml_path": str(yaml_path),
        "yaml_names": yaml_names,
        "processed_splits": processed_state,
        "wp": "WP3",
        "forbidden_in_wp3": list(FORBIDDEN_WP_CODES),
    }


def _bin_640(nw: float, nh: float) -> str:
    char = 640.0 * ((max(nw, 0.0) * max(nh, 0.0)) ** 0.5)
    if char < 32.0:
        return "lt_32"
    if char < 64.0:
        return "32_64"
    return "gt_64"


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
    invalid_boxes = 0
    missing_images = 0
    missing_labels = 0
    class_ids_seen: set[int] = set()
    small_est_640 = {
        name: {"lt_32": 0, "32_64": 0, "gt_64": 0, "total": 0} for name in CLASS_NAMES.values()
    }
    jpeg_status = "UNKNOWN"

    if not root.exists():
        errors.append(f"WP3 pavement root not found: {root}. {DATA_RECOVERY_INSTRUCTIONS}")
        return _report(
            root, yaml_path, errors, warnings, split_images, split_labels,
            box_ids, named_boxes, bad_lines, extra={
                "jpeg_status": "MISSING_ROOT",
                "invalid_boxes": 0,
                "missing_images": 0,
                "missing_labels": 0,
                "class_ids_seen": [],
                "data_recovery": DATA_RECOVERY_INSTRUCTIONS,
                "small_object_est_640": small_est_640,
            },
        )

    seen_stems: set[str] = set()
    for split in SPLITS:
        img_dir = root / "images" / split
        lbl_dir = root / "labels" / split
        images = _images(img_dir)
        labels = sorted(lbl_dir.glob("*.txt")) if lbl_dir.is_dir() else []
        split_images[split] = len(images)
        split_labels[split] = len(labels)
        if not images:
            warnings.append(f"{split}: no JPEG/PNG files in {img_dir}")
        if not labels:
            errors.append(f"{split}: no labels in {lbl_dir}")
        img_stems = {p.stem for p in images}
        lbl_stems = {p.stem for p in labels}
        missing_lbl = sorted(img_stems - lbl_stems)
        missing_img = sorted(lbl_stems - img_stems)
        if missing_lbl:
            missing_labels += len(missing_lbl)
            errors.append(f"{split}: {len(missing_lbl)} images missing labels (e.g. {missing_lbl[:3]})")
        if missing_img:
            missing_images += len(missing_img)
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
                    errors.append(f"{label}:{line_no}: malformed label, expected 5 YOLO fields")
                    continue
                raw_cls, *coords = parts
                try:
                    cls = int(float(raw_cls))
                    vals = [float(c) for c in coords]
                except ValueError:
                    bad_lines += 1
                    errors.append(f"{label}:{line_no}: malformed label, non-numeric fields")
                    continue
                class_ids_seen.add(cls)
                if cls not in ALLOWED_CLASS_IDS:
                    errors.append(
                        f"{label}:{line_no}: class id {cls} is not WP3 (must be 0=D20 or 1=D40). "
                        "D00/D10/D50/D60/D90 must not appear in pavement labels."
                    )
                    continue
                if any(not 0.0 <= v <= 1.0 for v in vals) or vals[2] <= 0 or vals[3] <= 0:
                    invalid_boxes += 1
                    errors.append(f"{label}:{line_no}: invalid box {vals}")
                    continue
                _, _, w, h = vals
                box_ids[cls] += 1
                named_boxes[CLASS_NAMES[cls]] += 1
                small_est_640[CLASS_NAMES[cls]]["total"] += 1
                small_est_640[CLASS_NAMES[cls]][_bin_640(w, h)] += 1

    extra_ids = sorted(class_ids_seen - ALLOWED_CLASS_IDS)
    if extra_ids:
        errors.append(f"non-WP3 class ids present: {extra_ids} (only 0=D20 and 1=D40 allowed)")

    images_total = sum(split_images.values())
    labels_total = sum(split_labels.values())
    if images_total == 0:
        jpeg_status = "GITIGNORED_OR_MISSING"
        errors.append(DATA_RECOVERY_INSTRUCTIONS)
    elif missing_images:
        jpeg_status = "PARTIAL"
    else:
        jpeg_status = "PRESENT"

    if yaml_path is not None:
        if not yaml_path.exists():
            errors.append(f"YAML not found: {yaml_path}")
        else:
            text = yaml_path.read_text()
            if "D20" not in text or "D40" not in text:
                errors.append(f"{yaml_path}: names must include D20 and D40")
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
                for code in FORBIDDEN_WP_CODES:
                    if code in list(mapped.values()):
                        errors.append(f"{yaml_path}: WP2/WP4 class {code} is not allowed in WP3")
            except ImportError:
                warnings.append("PyYAML not installed; YAML names checked as text only")

    count_errors_before = len(errors)
    if check_expected_counts and jpeg_status == "PRESENT" and not extra_ids and bad_lines == 0 and invalid_boxes == 0:
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
    elif check_expected_counts and jpeg_status == "PRESENT" and count_errors_before == 0:
        pass

    if labels_total and jpeg_status != "PRESENT":
        warnings.append(
            f"labels present ({labels_total}) but JPEGs are {jpeg_status}. "
            "Image counts 7380/1581/1582 cannot be confirmed until images are restored."
        )

    small_objects: dict[str, Any] | None = None
    if jpeg_status == "PRESENT":
        try:
            from src.eval_small_objects import analyze_root

            small_objects = analyze_root(root)
        except Exception as exc:  # pragma: no cover - optional
            warnings.append(f"small-object pixel bins unavailable: {exc}")

    return _report(
        root, yaml_path, errors, warnings, split_images, split_labels,
        box_ids, named_boxes, bad_lines,
        extra={
            "jpeg_status": jpeg_status,
            "invalid_boxes": invalid_boxes,
            "missing_images": missing_images,
            "missing_labels": missing_labels,
            "class_ids_seen": sorted(class_ids_seen),
            "data_recovery": DATA_RECOVERY_INSTRUCTIONS,
            "small_object_est_640": small_est_640,
            "small_objects_pixel": small_objects,
            "note_d40_small": (
                "Hypothesis (not a trained metric): D40 potholes are often small at "
                "imgsz=640. Compare small_object_est_640['D40'] and pixel bins when "
                "images are present. Model D40 AP is NOT_RUN until eval_wp3 status=OK."
            ),
        },
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
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    ok = not errors
    payload: dict[str, Any] = {
        "status": "OK" if ok else "FAIL",
        "verified_at_utc": datetime.now(timezone.utc).isoformat(),
        "root": str(root),
        "yaml": str(yaml_path) if yaml_path else None,
        "agent": "pavement",
        "wp": "WP3",
        "classes": {"0": "D20", "1": "D40"},
        "forbidden_classes": list(FORBIDDEN_WP_CODES),
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
            "Do not re-run prepare_dataset.py on an already-correct seed-42 folder."
        ),
    }
    if extra:
        payload.update(extra)
    return payload


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
            "errors": [DATA_RECOVERY_INSTRUCTIONS],
            "jpeg_status": "MISSING_ROOT",
            "expected_counts": EXPECTED_COUNTS,
            "data_recovery": DATA_RECOVERY_INSTRUCTIONS,
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
