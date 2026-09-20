"""Measure every Pascal VOC XML in an RDD extract. Does not invent class counts.

Reads object names and boxes from XML. Image-pixel sizes come from <size>,
so Pillow is not required for bbox / small-object stats.

Usage:
    python -m src.analyze_voc --source data/raw/rdd2022 --output reports/rdd_voc_analysis.json
"""
from __future__ import annotations

import argparse
import json
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from src.convert_rdd_voc import _build_rdd_to_dcode

COUNTRIES = (
    "China_Drone",
    "China_MotorBike",
    "Czech",
    "India",
    "Japan",
    "Norway",
    "United_States",
)

SMALL_PIXEL_AREA = 32 * 32
ISSUE_CAP = 2000


def _country(path: Path) -> str:
    for part in path.parts:
        if part in COUNTRIES:
            return part
    stem = path.stem
    for name in COUNTRIES:
        if stem.startswith(name):
            return name
    return "unknown"


def _pct(n: int, d: int) -> float:
    return round(100.0 * n / d, 2) if d else 0.0


def analyze_voc(source: Path, class_map_path: Path) -> dict[str, Any]:
    if not source.exists():
        raise SystemExit(f"VOC source not found: {source}")
    class_map = json.loads(class_map_path.read_text())
    rdd_to_dcode = _build_rdd_to_dcode(class_map)

    xmls = sorted(p for p in source.rglob("*.xml") if p.is_file())
    images = [
        p
        for p in source.rglob("*")
        if p.is_file() and p.suffix.lower() in {".jpg", ".jpeg", ".png"}
    ]

    raw_classes: Counter = Counter()
    mapped_classes: Counter = Counter()
    unmapped_classes: Counter = Counter()
    country_raw: dict[str, Counter] = defaultdict(Counter)
    country_xml: Counter = Counter()
    pixel_areas: list[float] = []
    norm_areas: list[float] = []
    box_widths: list[float] = []
    box_heights: list[float] = []
    img_widths: list[int] = []
    img_heights: list[int] = []
    small_by_class: Counter = Counter()
    small_by_mapped: Counter = Counter()

    issues: list[dict[str, Any]] = []
    issue_counts: Counter = Counter()
    empty_xml = 0
    parsed_ok = 0
    object_count = 0

    def _issue(kind: str, xml_path: Path, **extra: Any) -> None:
        issue_counts[kind] += 1
        if len(issues) < ISSUE_CAP:
            payload = {"kind": kind, "xml": str(xml_path)}
            payload.update(extra)
            issues.append(payload)

    for xml_path in xmls:
        country = _country(xml_path)
        country_xml[country] += 1
        try:
            root = ET.parse(xml_path).getroot()
        except ET.ParseError as exc:
            _issue("xml_parse_error", xml_path, error=str(exc))
            continue
        size = root.find("size")
        if size is None:
            _issue("missing_size", xml_path)
            continue
        try:
            width = float(size.findtext("width") or 0)
            height = float(size.findtext("height") or 0)
        except ValueError:
            _issue("invalid_size", xml_path)
            continue
        if width <= 0 or height <= 0:
            _issue("invalid_size", xml_path, width=width, height=height)
            continue
        img_widths.append(int(width))
        img_heights.append(int(height))
        objs = root.findall("object")
        if not objs:
            empty_xml += 1
        parsed_ok += 1
        for obj in objs:
            object_count += 1
            raw = (obj.findtext("name") or "").strip()
            raw_key = raw if raw else "<empty>"
            raw_classes[raw_key] += 1
            country_raw[country][raw_key] += 1
            box = obj.find("bndbox")
            if box is None:
                _issue("missing_bndbox", xml_path, raw_class=raw)
                continue
            try:
                xmin = float(box.findtext("xmin") or 0)
                ymin = float(box.findtext("ymin") or 0)
                xmax = float(box.findtext("xmax") or 0)
                ymax = float(box.findtext("ymax") or 0)
            except ValueError:
                _issue("non_numeric_box", xml_path, raw_class=raw)
                continue
            xmin, xmax = sorted((xmin, xmax))
            ymin, ymax = sorted((ymin, ymax))
            bw = xmax - xmin
            bh = ymax - ymin
            if bw <= 1 or bh <= 1:
                _issue("degenerate_box", xml_path, raw_class=raw, bw=bw, bh=bh)
                continue
            pixel_area = bw * bh
            pixel_areas.append(pixel_area)
            box_widths.append(bw)
            box_heights.append(bh)
            norm_areas.append((bw / width) * (bh / height))
            dcode = rdd_to_dcode.get(raw.upper())
            if dcode is None:
                unmapped_classes[raw_key] += 1
            else:
                mapped_classes[dcode] += 1
            if pixel_area < SMALL_PIXEL_AREA:
                small_by_class[raw_key] += 1
                if dcode:
                    small_by_mapped[dcode] += 1

    def _stats(values: list[float]) -> dict[str, float | int | None]:
        if not values:
            return {"count": 0, "min": None, "max": None, "mean": None}
        return {
            "count": len(values),
            "min": round(min(values), 6),
            "max": round(max(values), 6),
            "mean": round(sum(values) / len(values), 6),
        }

    present_mapped = set(mapped_classes)
    return {
        "analyzed_at_utc": datetime.now(timezone.utc).isoformat(),
        "source": str(source.resolve()),
        "xml_count": len(xmls),
        "image_file_count": len(images),
        "xml_parsed_ok": parsed_ok,
        "xml_empty_no_objects": empty_xml,
        "object_count": object_count,
        "raw_class_distribution": dict(raw_classes),
        "mapped_tariqmap_distribution": dict(mapped_classes),
        "unmapped_class_distribution": dict(unmapped_classes),
        "d43_count_raw": int(raw_classes.get("D43", 0)),
        "d44_count_raw": int(raw_classes.get("D44", 0)),
        "d50_rdd_other_count_raw": int(raw_classes.get("D50", 0)),
        "d90_count_raw": int(raw_classes.get("D90", 0)),
        "d50_mapped_status": "PRESENT" if "D50" in present_mapped else "ABSENT",
        "d60_mapped_status": "PRESENT" if "D60" in present_mapped else "ABSENT",
        "d90_mapped_status": "ABSENT",
        "xml_per_country": dict(country_xml),
        "raw_classes_per_country": {k: dict(v) for k, v in country_raw.items()},
        "bbox_pixel_area": _stats(pixel_areas),
        "bbox_pixel_width": _stats(box_widths),
        "bbox_pixel_height": _stats(box_heights),
        "bbox_normalized_area": _stats(norm_areas),
        "image_sizes_from_xml": {
            "sampled": len(img_widths),
            "width_min": min(img_widths) if img_widths else None,
            "width_max": max(img_widths) if img_widths else None,
            "height_min": min(img_heights) if img_heights else None,
            "height_max": max(img_heights) if img_heights else None,
        },
        "small_objects_area_lt_32px": {
            "by_raw_class": dict(small_by_class),
            "by_mapped_class": dict(small_by_mapped),
            "total": int(sum(small_by_class.values())),
            "percent_of_valid_boxes": _pct(int(sum(small_by_class.values())), len(pixel_areas)),
        },
        "issue_counts": dict(issue_counts),
        "issues_sample": issues,
        "weak_class_dataset_notes": _weak_class_notes(mapped_classes, small_by_mapped, raw_classes),
        "verdict": (
            "LABELED_VOC — run convert_rdd_voc.py"
            if parsed_ok and mapped_classes
            else "STOP — no usable VOC objects"
        ),
    }


def _weak_class_notes(
    mapped: Counter,
    small_mapped: Counter,
    raw: Counter,
) -> dict[str, Any]:
    total = sum(mapped.values()) or 1
    notes = []
    for code in ("D00", "D10", "D20", "D40", "D50", "D60"):
        n = int(mapped.get(code, 0))
        small = int(small_mapped.get(code, 0))
        notes.append(
            {
                "class": code,
                "mapped_boxes": n,
                "share_of_mapped_boxes_pct": _pct(n, total),
                "small_boxes": small,
                "small_pct_of_class": _pct(small, n),
            }
        )
    return {
        "status": "DATASET_SIDE_ONLY — no trained detector, so this is imbalance/size risk not mAP",
        "classes": notes,
        "raw_d43": int(raw.get("D43", 0)),
        "raw_d44": int(raw.get("D44", 0)),
        "raw_d50_other_excluded": int(raw.get("D50", 0)),
        "raw_d90": int(raw.get("D90", 0)),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument(
        "--class-map",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "config" / "source-class-map.json",
    )
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()
    report = analyze_voc(args.source, args.class_map)
    text = json.dumps(report, indent=2)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)


if __name__ == "__main__":
    main()
