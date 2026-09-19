"""Dataset audit for TariqMap.

Produces a machine-readable JSON report to training/reports/ and a versioned
manifest to training/manifests/.  Run BEFORE any training or label-mapping work.

Usage:
    python -m src.audit_dataset \\
        --dataset ../../Global_Potholes_Dataset-image \\
        --output-dir reports \\
        --manifest-dir manifests \\
        --sample-hashes 500

Exit codes:
    0  Audit passed  (annotations present and non-zero)
    1  Audit failed  (no annotations found — action required before training)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Optional: PIL for image dimension inspection (fails gracefully without it)
try:
    from PIL import Image as PILImage
    _PIL_AVAILABLE = True
except ImportError:
    _PIL_AVAILABLE = False


# ---------------------------------------------------------------------------
# Annotation-format probes
# ---------------------------------------------------------------------------

_ANNOTATION_EXTENSIONS: dict[str, str] = {
    ".txt":  "yolo_txt",
    ".json": "coco_json_or_labelme",
    ".xml":  "pascal_voc",
    ".csv":  "csv",
}

_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}


def _probe_annotation_format(directory: Path) -> dict[str, int]:
    """Walk directory tree; count annotation files by type."""
    counts: dict[str, int] = {}
    for ext, fmt in _ANNOTATION_EXTENSIONS.items():
        n = sum(1 for _ in directory.rglob(f"*{ext}"))
        if n:
            counts[fmt] = n
    return counts


def _count_images(directory: Path) -> tuple[int, Counter]:
    """Return (total_image_count, ext_counter)."""
    ext_counter: Counter = Counter()
    for f in directory.rglob("*"):
        if f.is_file() and f.suffix.lower() in _IMAGE_EXTENSIONS:
            ext_counter[f.suffix.lower()] += 1
    return sum(ext_counter.values()), ext_counter


def _sample_md5_hashes(directory: Path, max_samples: int) -> tuple[int, list[str]]:
    """Sample up to max_samples images and return (duplicate_count, sample_hashes)."""
    files = [f for f in directory.rglob("*")
             if f.is_file() and f.suffix.lower() in _IMAGE_EXTENSIONS]
    files = files[:max_samples]
    hashes: list[str] = []
    for f in files:
        try:
            md5 = hashlib.md5(f.read_bytes()).hexdigest()
            hashes.append(md5)
        except OSError:
            hashes.append("ERROR")
    duplicates = len(hashes) - len(set(hashes))
    return duplicates, hashes


def _sample_dimensions(directory: Path, max_samples: int = 50) -> dict[str, Any]:
    """Inspect image dimensions for the first max_samples images."""
    if not _PIL_AVAILABLE:
        return {"status": "skipped — Pillow not installed"}

    files = [f for f in directory.rglob("*")
             if f.is_file() and f.suffix.lower() in _IMAGE_EXTENSIONS]
    files = files[:max_samples]

    widths, heights = [], []
    errors = 0
    for f in files:
        try:
            with PILImage.open(f) as im:
                widths.append(im.width)
                heights.append(im.height)
        except Exception:
            errors += 1

    if not widths:
        return {"status": "no readable images"}

    return {
        "sampled": len(widths),
        "errors": errors,
        "width_min": min(widths),
        "width_max": max(widths),
        "width_mean": round(sum(widths) / len(widths), 1),
        "height_min": min(heights),
        "height_max": max(heights),
        "height_mean": round(sum(heights) / len(heights), 1),
    }


def _detect_license(directory: Path) -> str:
    """Look for a LICENSE / README with attribution text."""
    for name in ("LICENSE", "LICENSE.txt", "LICENSE.md", "README.md", "README.txt"):
        f = directory / name
        if f.exists():
            snippet = f.read_text(errors="replace")[:400]
            return f"Found {name}: {snippet!r}"
    return "No license file found in dataset root"


# ---------------------------------------------------------------------------
# Main audit logic
# ---------------------------------------------------------------------------

def audit(dataset_path: Path, sample_hashes: int) -> dict[str, Any]:
    """Run full audit and return the result dictionary."""
    if not dataset_path.exists():
        print(f"[audit] ERROR: Dataset path not found: {dataset_path}")
        sys.exit(2)

    total_images, ext_counter = _count_images(dataset_path)
    annotations = _probe_annotation_format(dataset_path)
    duplicate_count, hashes = _sample_md5_hashes(dataset_path, sample_hashes)
    dimensions = _sample_dimensions(dataset_path)
    license_text = _detect_license(dataset_path)

    annotation_status = "UNLABELED" if not annotations else "LABELED"

    report: dict[str, Any] = {
        "audit_version": "1.0",
        "audit_date_utc": datetime.now(timezone.utc).isoformat(),
        "dataset_path": str(dataset_path.resolve()),
        "image_count": total_images,
        "image_extensions": dict(ext_counter),
        "annotation_status": annotation_status,
        "annotation_files_found": annotations,
        "annotation_classes_verified": False,
        "class_mapping": "NOT_POSSIBLE — no annotations",
        "duplicate_hash_sample": {
            "sample_size": len(hashes),
            "duplicates_in_sample": duplicate_count,
        },
        "image_dimensions": dimensions,
        "train_val_test_split": "NOT_PRESENT — flat directory",
        "license": license_text,
        "verdict": (
            "STOP: Dataset is unlabeled. "
            "Annotate with CVAT, Roboflow, or LabelStudio, then re-run this audit. "
            "Do not attempt to train until annotation_status == LABELED."
            if annotation_status == "UNLABELED"
            else "OK — proceed with class-mapping verification."
        ),
        "actionable_next_steps": [
            "1. Annotate images using CVAT (https://cvat.ai) or Roboflow with class D40 (pothole) at minimum.",
            "2. Export annotations in YOLO format.",
            "3. Run audit_dataset.py again to verify annotation count.",
            "4. Run prepare_dataset.py with --class-map to split into agent datasets.",
            "5. Run train.py for each agent after dataset validation passes.",
        ] if annotation_status == "UNLABELED" else [
            "1. Verify class IDs in annotation files against the canonical D-code map.",
            "2. Run prepare_dataset.py --class-map to split into agent datasets.",
        ],
    }

    return report


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="TariqMap dataset audit tool")
    parser.add_argument(
        "--dataset",
        type=Path,
        default=Path(__file__).resolve().parents[3] / "Global_Potholes_Dataset-image",
        help="Root directory of the dataset to audit",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "reports",
        help="Directory to write the audit JSON report",
    )
    parser.add_argument(
        "--manifest-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "manifests",
        help="Directory to write the versioned dataset manifest",
    )
    parser.add_argument(
        "--sample-hashes",
        type=int,
        default=500,
        help="Number of images to hash for duplicate detection",
    )
    args = parser.parse_args()

    print(f"[audit] Inspecting: {args.dataset}")
    report = audit(args.dataset, args.sample_hashes)

    # Write report
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report_path = args.output_dir / "global_potholes_audit.json"
    report_path.write_text(json.dumps(report, indent=2))
    print(f"[audit] Report written -> {report_path}")

    # Write manifest
    args.manifest_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "manifest_version": "1.0",
        "dataset_name": "global_potholes_dataset-image",
        "source_path": str(Path(args.dataset).resolve()),
        "image_count": report.get("image_count", 0),
        "annotation_status": report.get("annotation_status", "UNKNOWN"),
        "class_mapping": report.get("class_mapping", "UNKNOWN"),
        "audit_date_utc": report.get("audit_date_utc", ""),
        "audit_report_path": str(report_path),
        "tariqmap_agent_mapping": {
            "D40": {
                "status": "REQUIRES_ANNOTATION",
                "note": "Images may contain potholes but no labels exist yet"
            }
        },
    }
    manifest_path = args.manifest_dir / "global_potholes_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))
    print(f"[audit] Manifest written -> {manifest_path}")

    # Summary
    print("\n" + "=" * 60)
    print(f"  Image count  : {report['image_count']:,}")
    print(f"  Annotations  : {report['annotation_status']}")
    print(f"  Verdict      : {report['verdict'][:80]}...")
    print("=" * 60)

    if report["annotation_status"] == "UNLABELED":
        print("\n[STOP] No annotations found. See next steps above.\n")
        sys.exit(1)
    else:
        print("\n[OK] Dataset has annotations. Verify class mapping next.\n")
        sys.exit(0)


if __name__ == "__main__":
    main()
