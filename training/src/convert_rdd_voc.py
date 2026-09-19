"""Convert RDD2022 / RDD2024 Pascal VOC XML annotations to YOLO txt.

Only maps classes that are scientifically justified in source-class-map.json:
  D00→D00, D10→D10, D20→D20, D40→D40, D44→D50, D43→D60
D90 is never produced.

Usage:
    python -m src.convert_rdd_voc \\
        --source /path/to/RDD2022 \\
        --output data/raw/rdd_yolo \\
        --class-map config/source-class-map.json
"""
from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
from typing import Any

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

# Canonical YOLO class ids for a unified 7-class dataset.
# D90 is reserved but never written by this converter.
UNIFIED_IDS = {
    "D00": 0,
    "D10": 1,
    "D20": 2,
    "D40": 3,
    "D50": 4,
    "D60": 5,
    "D90": 6,
}


def _build_rdd_to_dcode(class_map: dict[str, Any]) -> dict[str, str]:
    lookup: dict[str, str] = {}
    for dcode, info in class_map.items():
        if dcode.startswith("_"):
            continue
        for name in info.get("rdd2022_names", []):
            lookup[str(name).upper()] = dcode
        lookup[dcode.upper()] = dcode
        for alias in info.get("aliases", []):
            lookup[str(alias).upper()] = dcode
    # Guard: RDD's own D50-other must NOT become TariqMap D50.
    # Only D44 maps to D50. If the XML says D50, exclude it.
    lookup.pop("D50", None)
    lookup["D44"] = "D50"
    lookup["D43"] = "D60"
    lookup["D00"] = "D00"
    lookup["D10"] = "D10"
    lookup["D20"] = "D20"
    lookup["D40"] = "D40"
    return lookup


def voc_xml_to_yolo_lines(
    xml_path: Path,
    rdd_to_dcode: dict[str, str],
    exclusions: list[dict[str, Any]],
) -> tuple[list[str], Counter]:
    tree = ET.parse(xml_path)
    root = tree.getroot()
    size = root.find("size")
    if size is None:
        raise ValueError(f"{xml_path}: missing <size>")
    width = float(size.findtext("width") or 0)
    height = float(size.findtext("height") or 0)
    if width <= 0 or height <= 0:
        raise ValueError(f"{xml_path}: invalid size {width}x{height}")

    counts: Counter = Counter()
    lines: list[str] = []
    for obj in root.findall("object"):
        raw = (obj.findtext("name") or "").strip()
        dcode = rdd_to_dcode.get(raw.upper())
        if dcode is None:
            exclusions.append({
                "xml": str(xml_path),
                "raw_class": raw,
                "reason": "No scientifically justified mapping to TariqMap taxonomy",
            })
            continue
        if dcode == "D90":
            exclusions.append({
                "xml": str(xml_path),
                "raw_class": raw,
                "reason": "D90 is absent from RDD — refusing to emit labels",
            })
            continue
        box = obj.find("bndbox")
        if box is None:
            continue
        xmin = float(box.findtext("xmin") or 0)
        ymin = float(box.findtext("ymin") or 0)
        xmax = float(box.findtext("xmax") or 0)
        ymax = float(box.findtext("ymax") or 0)
        xmin, xmax = sorted((xmin, xmax))
        ymin, ymax = sorted((ymin, ymax))
        xmin = max(0.0, min(xmin, width))
        xmax = max(0.0, min(xmax, width))
        ymin = max(0.0, min(ymin, height))
        ymax = max(0.0, min(ymax, height))
        bw = xmax - xmin
        bh = ymax - ymin
        if bw <= 1 or bh <= 1:
            exclusions.append({
                "xml": str(xml_path),
                "raw_class": raw,
                "reason": "degenerate box",
            })
            continue
        cx = (xmin + xmax) / 2.0 / width
        cy = (ymin + ymax) / 2.0 / height
        nw = bw / width
        nh = bh / height
        cls_id = UNIFIED_IDS[dcode]
        lines.append(f"{cls_id} {cx:.6f} {cy:.6f} {nw:.6f} {nh:.6f}")
        counts[dcode] += 1
    return lines, counts


def _find_image(xml_path: Path, images_root: Path | None) -> Path | None:
    stem = xml_path.stem
    search_roots = [xml_path.parent]
    if images_root is not None:
        search_roots.insert(0, images_root)
    for root in search_roots:
        for ext in IMAGE_EXTENSIONS:
            candidate = root / f"{stem}{ext}"
            if candidate.exists():
                return candidate
            # RDD often stores images in a sibling JPEGImages / images folder
            for sub in ("JPEGImages", "images", "Image"):
                candidate = root.parent / sub / f"{stem}{ext}"
                if candidate.exists():
                    return candidate
    matches = list((images_root or xml_path.parent).rglob(f"{stem}.*"))
    for m in matches:
        if m.suffix.lower() in IMAGE_EXTENSIONS:
            return m
    return None


def convert(
    source: Path,
    output: Path,
    class_map_path: Path,
) -> dict[str, Any]:
    class_map = json.loads(class_map_path.read_text())
    rdd_to_dcode = _build_rdd_to_dcode(class_map)

    xmls = sorted(source.rglob("*.xml"))
    if not xmls:
        raise SystemExit(
            f"No Pascal VOC XML files under {source}. "
            "RDD2022 annotations are XML, not the unlabeled Global Potholes dump."
        )

    images_out = output / "images"
    labels_out = output / "labels"
    images_out.mkdir(parents=True, exist_ok=True)
    labels_out.mkdir(parents=True, exist_ok=True)

    exclusions: list[dict[str, Any]] = []
    class_counts: Counter = Counter()
    converted = 0
    skipped_no_image = 0
    skipped_empty = 0

    for xml_path in xmls:
        try:
            lines, counts = voc_xml_to_yolo_lines(xml_path, rdd_to_dcode, exclusions)
        except Exception as exc:  # noqa: BLE001
            exclusions.append({"xml": str(xml_path), "reason": str(exc)})
            continue
        if not lines:
            skipped_empty += 1
            continue
        image = _find_image(xml_path, source)
        if image is None:
            skipped_no_image += 1
            exclusions.append({"xml": str(xml_path), "reason": "matching image not found"})
            continue
        dest_img = images_out / image.name
        dest_lbl = labels_out / f"{image.stem}.txt"
        if not dest_img.exists():
            try:
                dest_img.write_bytes(image.read_bytes())
            except OSError:
                # Fall back to symlink when copy is expensive / not needed for tests
                dest_img.symlink_to(image.resolve())
        dest_lbl.write_text("\n".join(lines) + "\n")
        class_counts.update(counts)
        converted += 1

    summary = {
        "source": str(source.resolve()),
        "output": str(output.resolve()),
        "xml_files": len(xmls),
        "converted_images": converted,
        "skipped_empty_after_mapping": skipped_empty,
        "skipped_missing_image": skipped_no_image,
        "class_distribution": dict(class_counts),
        "d90_emitted": class_counts.get("D90", 0),
        "exclusion_count": len(exclusions),
        "mapping": {
            "D00": "D00",
            "D10": "D10",
            "D20": "D20",
            "D40": "D40",
            "D43": "D60 (white line blur → faded lane) if present",
            "D44": "D50 (crosswalk blur → faded crossing) if present",
            "D90": "NOT MAPPED — absent from RDD",
        },
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / "conversion_summary.json").write_text(json.dumps(summary, indent=2))
    (output / "exclusion_report.json").write_text(json.dumps(exclusions, indent=2))
    print(json.dumps(summary, indent=2))
    if converted == 0:
        raise SystemExit("STOP: no labeled images converted. Cannot train.")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert RDD VOC XML to YOLO")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--class-map",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "config" / "source-class-map.json",
    )
    args = parser.parse_args()
    convert(args.source, args.output, args.class_map)


if __name__ == "__main__":
    main()
    sys.exit(0)
