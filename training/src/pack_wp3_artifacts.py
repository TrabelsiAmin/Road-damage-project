"""Zip WP3 training artefacts (weights, reports, plots). Never zips the dataset.

Usage:
    python -m src.pack_wp3_artifacts --output wp3_training_artifacts.zip
"""
from __future__ import annotations

import argparse
import json
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

def collect(training_root: Path) -> list[Path]:
    found: list[Path] = []
    for rel in (
        training_root / "reports" / "wp3",
        training_root / "runs" / "wp3_baseline",
        training_root / "runs" / "wp3_improved",
    ):
        if rel.is_dir():
            for path in rel.rglob("*"):
                if not path.is_file():
                    continue
                if path.suffix.lower() in {".json", ".md", ".png", ".csv", ".yaml", ".yml", ".pt", ".txt"}:
                    found.append(path)
    yaml = training_root / "config" / "pavement.yaml"
    if yaml.is_file():
        found.append(yaml)
    return sorted({p.resolve() for p in found})


def pack(training_root: Path, output: Path) -> dict[str, Any]:
    files = collect(training_root)
    weights = [p for p in files if p.suffix == ".pt"]
    manifest = {
        "packed_at_utc": datetime.now(timezone.utc).isoformat(),
        "wp": "WP3",
        "output": str(output),
        "file_count": len(files),
        "weight_files": [str(p.relative_to(training_root)) for p in weights],
        "included": [str(p.relative_to(training_root)) for p in files],
        "excluded": ["data/processed/** (dataset images/labels are NOT packed)"],
        "status": "OK" if weights else "NOT_RUN",
        "note": (
            "Empty zip payload means training has not been executed. "
            "Do not commit this zip or .pt files to git."
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
    args = parser.parse_args()
    pack(args.training_root, args.output)


if __name__ == "__main__":
    main()
