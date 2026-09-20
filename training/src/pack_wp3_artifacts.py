"""Zip / stage WP3 training artefacts. Never packs the dataset.

Usage:
    python -m src.pack_wp3_artifacts --output wp3_training_artifacts.zip
    python -m src.pack_wp3_artifacts --stage reports/wp3/artifacts --skip-zip
"""
from __future__ import annotations

import argparse
import json
import shutil
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ARTIFACT_SUFFIXES = {
    ".json",
    ".md",
    ".png",
    ".csv",
    ".yaml",
    ".yml",
    ".pt",
    ".txt",
    ".tflite",
}

PLOT_GLOBS = (
    "results.csv",
    "confusion_matrix.png",
    "confusion_matrix_normalized.png",
    "BoxPR_curve.png",
    "PR_curve.png",
    "BoxP_curve.png",
    "BoxR_curve.png",
    "F1_curve.png",
    "results.png",
    "labels.jpg",
)


def collect(training_root: Path) -> list[Path]:
    found: list[Path] = []
    search_dirs = [training_root / "reports" / "wp3"]
    runs = training_root / "runs"
    if runs.is_dir():
        search_dirs.extend(sorted(p for p in runs.glob("wp3_*") if p.is_dir()))
    for rel in search_dirs:
        if rel.is_dir():
            for path in rel.rglob("*"):
                if not path.is_file():
                    continue
                if path.suffix.lower() in ARTIFACT_SUFFIXES:
                    found.append(path)
    yaml = training_root / "config" / "pavement.yaml"
    if yaml.is_file():
        found.append(yaml)
    return sorted({p.resolve() for p in found})


def stage_artifacts(
    training_root: Path,
    dest: Path,
    selected_best: Path | None = None,
) -> dict[str, Any]:
    """Copy best.pt, results.csv, metrics, plots, confusion, PR, tflite, config."""
    dest.mkdir(parents=True, exist_ok=True)
    copied: list[str] = []

    def _copy(src: Path, name: str) -> None:
        if not src.is_file():
            return
        target = dest / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, target)
        copied.append(str(target.relative_to(dest)))

    cfg = training_root / "config" / "pavement.yaml"
    _copy(cfg, "pavement.yaml")

    if selected_best and selected_best.is_file():
        _copy(selected_best, "best.pt")

    runs = training_root / "runs"
    if runs.is_dir():
        for run_dir in sorted(p for p in runs.glob("wp3_*") if p.is_dir()):
            prefix = run_dir.name
            _copy(run_dir / "weights" / "best.pt", f"{prefix}_best.pt")
            _copy(run_dir / "weights" / "last.pt", f"{prefix}_last.pt")
            for name in PLOT_GLOBS:
                _copy(run_dir / name, f"{prefix}_{name}")
            for extra in run_dir.glob("*PR*.png"):
                _copy(extra, f"{prefix}_{extra.name}")
            for extra in run_dir.glob("*confusion*.png"):
                _copy(extra, f"{prefix}_{extra.name}")

    reports = training_root / "reports" / "wp3"
    if reports.is_dir():
        for path in reports.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix.lower() in {".json", ".md", ".csv", ".png", ".tflite", ".yaml", ".yml"}:
                rel = path.relative_to(reports)
                _copy(path, str(Path("reports") / rel))

    manifest = {
        "staged_at_utc": datetime.now(timezone.utc).isoformat(),
        "wp": "WP3",
        "dest": str(dest),
        "copied": copied,
        "status": "OK" if any(n.endswith(".pt") for n in copied) else "NOT_RUN",
        "excluded": ["data/processed/** (dataset is NOT copied)", "do not git-commit *.pt / *.tflite"],
        "note": "Training NOT YET EXECUTED if no best.pt is listed.",
    }
    (dest / "artifact_manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest


def pack(training_root: Path, output: Path) -> dict[str, Any]:
    files = collect(training_root)
    weights = [p for p in files if p.suffix == ".pt"]
    tflite = [p for p in files if p.suffix == ".tflite"]
    manifest = {
        "packed_at_utc": datetime.now(timezone.utc).isoformat(),
        "wp": "WP3",
        "output": str(output),
        "file_count": len(files),
        "weight_files": [str(p.relative_to(training_root)) for p in weights],
        "tflite_files": [str(p.relative_to(training_root)) for p in tflite],
        "included": [str(p.relative_to(training_root)) for p in files],
        "excluded": ["data/processed/** (dataset images/labels are NOT packed)"],
        "status": "OK" if weights else "NOT_RUN",
        "note": (
            "Empty zip payload means training has not been executed. "
            "Do not commit this zip or .pt / .tflite files to git."
        ),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("manifest.json", json.dumps(manifest, indent=2))
        for path in files:
            zf.write(path, arcname=str(path.relative_to(training_root)))
    print(json.dumps(manifest, indent=2))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--training-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("wp3_training_artifacts.zip"),
    )
    parser.add_argument(
        "--stage",
        type=Path,
        default=None,
        help="Copy artefacts into this directory (reports/wp3/artifacts)",
    )
    parser.add_argument("--selected-best", type=Path, default=None)
    parser.add_argument("--skip-zip", action="store_true")
    args = parser.parse_args()
    if args.stage:
        print(json.dumps(stage_artifacts(args.training_root, args.stage, args.selected_best), indent=2))
    if not args.skip_zip:
        pack(args.training_root, args.output)


if __name__ == "__main__":
    main()
