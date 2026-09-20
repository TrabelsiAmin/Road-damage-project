"""Summarize the official CRDDC File_List (inventory of files, not class labels).

This counts XML and image *paths* listed by Figshare. It does not parse
bounding boxes. Class distribution comes from analyze_voc.py after extract.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

COUNTRIES = (
    "China_Drone",
    "China_MotorBike",
    "Czech",
    "India",
    "Japan",
    "Norway",
    "United_States",
)

FOLDER_RE = re.compile(r"[+\\]---([A-Za-z0-9_]+)\s*$")
FILE_RE = re.compile(r"([A-Za-z0-9_.-]+\.[A-Za-z0-9]+)\s*$")

IMAGE_EXT = {".jpg", ".jpeg", ".png"}


def summarize(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise SystemExit(f"File list not found: {path}")

    per: dict[str, dict[str, dict[str, int]]] = {
        c: {
            "train": {"xml": 0, "image": 0},
            "test": {"xml": 0, "image": 0},
            "other": {"xml": 0, "image": 0},
        }
        for c in COUNTRIES
    }
    extras: dict[str, int] = defaultdict(int)
    country: str | None = None
    split: str = "other"

    for line in path.read_text(errors="replace").splitlines():
        folder = FOLDER_RE.search(line)
        if folder:
            name = folder.group(1)
            if name in COUNTRIES:
                country = name
                split = "other"
            elif name in {"train", "test"}:
                split = name
            continue
        match = FILE_RE.search(line)
        if not match:
            continue
        fname = match.group(1)
        suffix = Path(fname).suffix.lower()
        bucket = split if split in {"train", "test"} else "other"
        ctry = country if country in per else None
        if suffix == ".xml":
            if ctry:
                per[ctry][bucket]["xml"] += 1
            else:
                extras[fname] += 1
        elif suffix in IMAGE_EXT:
            if ctry:
                per[ctry][bucket]["image"] += 1
            else:
                extras[fname] += 1
        else:
            extras[fname] += 1

    xml_total = 0
    image_total = 0
    xml_train = 0
    images_test = 0
    for c, splits in per.items():
        xml_total += splits["train"]["xml"] + splits["test"]["xml"] + splits["other"]["xml"]
        image_total += splits["train"]["image"] + splits["test"]["image"] + splits["other"]["image"]
        xml_train += splits["train"]["xml"]
        images_test += splits["test"]["image"]

    return {
        "source": str(path.resolve()),
        "kind": "official_file_inventory_not_class_labels",
        "xml_total": xml_total,
        "image_total": image_total,
        "xml_train": xml_train,
        "unlabeled_test_images": images_test,
        "per_country": per,
        "extra_non_country_files": dict(extras),
        "note": (
            "Counts come from File_List_CRDDC_RDD2022.txt (Figshare file 38030826). "
            "They are file-path inventory, not bounding-box class distribution. "
            "Test images have no XML in this listing. Do not treat extra JPEGs as labels."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file-list", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()
    report = summarize(args.file_list)
    text = json.dumps(report, indent=2)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)


if __name__ == "__main__":
    main()
