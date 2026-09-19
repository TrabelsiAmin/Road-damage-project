"""Download / locate a labeled RDD dump. Never fetches the unlabeled pothole set.

Official sources (user must accept the RDD license):
  - RDD2022 figshare: https://figshare.com/articles/dataset/RDD2022/16680289
  - RoadDamageDetector: https://github.com/sekilab/RoadDamageDetector

This script does not scrape paywalled mirrors. If the archive is not on disk
it prints exact next steps and exits non-zero.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


OFFICIAL = {
    "rdd2022_figshare": "https://figshare.com/articles/dataset/RDD2022/16680289",
    "rdd2022_paper": "https://arxiv.org/abs/2209.08538",
    "github": "https://github.com/sekilab/RoadDamageDetector",
}


def locate(root: Path) -> dict:
    xml = list(root.rglob("*.xml")) if root.exists() else []
    images = [
        p
        for p in (root.rglob("*") if root.exists() else [])
        if p.suffix.lower() in {".jpg", ".jpeg", ".png"}
    ]
    return {
        "path": str(root),
        "exists": root.exists(),
        "xml_count": len(xml),
        "image_count": len(images),
        "usable": len(xml) > 0,
        "official_sources": OFFICIAL,
        "note": (
            "Labeled RDD VOC XML found."
            if xml
            else "Place an RDD2022/RDD2024 extract here (JPEG + XML). "
            "Do not point this tool at Global_Potholes_Dataset-image."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dest",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "data" / "raw" / "rdd2022",
    )
    args = parser.parse_args()
    report = locate(args.dest)
    print(json.dumps(report, indent=2))
    print("\nTo obtain RDD2022:")
    print(f"  1. Download from {OFFICIAL['rdd2022_figshare']}")
    print(f"  2. Extract into {args.dest}")
    print("  3. python -m src.convert_rdd_voc --source <extract> --output data/raw/rdd_yolo")
    print("  4. python -m src.analyze_labeled_dataset --dataset data/raw/rdd_yolo")
    print("  5. python -m src.prepare_dataset --source data/raw/rdd_yolo --output data/processed --class-map config/source-class-map.json")
    if not report["usable"]:
        sys.exit(2)


if __name__ == "__main__":
    main()
