#!/usr/bin/env python3
"""Validate a candidate annotation file. Does not write labels or touch images.

Exit 0 when the document has no findings. Exit 2 when it does, or when the
output path would land inside Global_Potholes_Dataset-image.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCHEMA_ID = "tariqmap-annotations-1"
REVIEW = {"unreviewed", "accepted", "rejected"}


def _err(code: str, message: str, **extra) -> dict:
    item = {"code": code, "message": message}
    item.update(extra)
    return item


def validate_document(doc: dict, image_root: Path | None = None) -> list[dict]:
    findings: list[dict] = []
    if not isinstance(doc, dict):
        return [_err("invalid_structure", "document is not an object")]
    info = doc.get("info")
    if not isinstance(info, dict):
        findings.append(_err("missing_provenance", "info object is missing"))
        info = {}
    if info.get("annotation_schema") != SCHEMA_ID:
        findings.append(_err("invalid_structure", "info.annotation_schema must be tariqmap-annotations-1"))
    if not str(info.get("annotation_version") or "").strip():
        findings.append(_err("missing_provenance", "info.annotation_version is missing"))
    if not str(info.get("provenance") or "").strip():
        findings.append(_err("missing_provenance", "info.provenance is missing"))

    images = doc.get("images")
    annotations = doc.get("annotations")
    categories = doc.get("categories")
    if not isinstance(images, list) or not isinstance(annotations, list) or not isinstance(categories, list):
        findings.append(_err("invalid_structure", "images, annotations, and categories must be arrays"))
        return findings

    image_by_id: dict[int, dict] = {}
    for image in images:
        if not isinstance(image, dict) or not isinstance(image.get("id"), int):
            findings.append(_err("invalid_structure", "image is missing an integer id"))
            continue
        image_id = image["id"]
        if image_id in image_by_id:
            findings.append(_err("duplicate_image_id", "image id is repeated", image_id=image_id))
        image_by_id[image_id] = image
        if not str(image.get("file_name") or "").strip():
            findings.append(_err("invalid_structure", "image file_name is missing", image_id=image_id))
        width, height = image.get("width"), image.get("height")
        if not isinstance(width, int) or not isinstance(height, int) or width < 1 or height < 1:
            findings.append(_err("invalid_structure", "image width and height must be positive integers", image_id=image_id))
        if image_root is not None:
            name = str(image.get("file_name") or "")
            if not name or not (image_root / name).is_file():
                findings.append(_err("missing_image", "image file is not in the image root", image_id=image_id, file_name=name))

    category_ids = set()
    for cat in categories:
        if not isinstance(cat, dict) or not isinstance(cat.get("id"), int):
            findings.append(_err("invalid_class", "category is missing an integer id"))
            continue
        category_ids.add(cat["id"])
        if not str(cat.get("name") or "").strip():
            findings.append(_err("invalid_class", "category name is missing", category_id=cat["id"]))

    seen_ann = set()
    boxes_for: dict[int, int] = {image_id: 0 for image_id in image_by_id}
    for ann in annotations:
        if not isinstance(ann, dict) or not isinstance(ann.get("id"), int):
            findings.append(_err("invalid_structure", "annotation is missing an integer id"))
            continue
        if ann["id"] in seen_ann:
            findings.append(_err("duplicate_annotation_id", "annotation id is repeated", annotation_id=ann["id"]))
        seen_ann.add(ann["id"])
        image_id = ann.get("image_id")
        image = image_by_id.get(image_id) if isinstance(image_id, int) else None
        if image is None:
            findings.append(_err("invalid_structure", "annotation image_id does not match an image", annotation_id=ann["id"]))
        else:
            boxes_for[image_id] = boxes_for.get(image_id, 0) + 1
        if ann.get("category_id") not in category_ids:
            findings.append(_err("invalid_class", "category_id is not in categories", annotation_id=ann["id"]))
        if not str(ann.get("annotator_id") or "").strip():
            findings.append(_err("missing_provenance", "annotator_id is missing", annotation_id=ann["id"]))
        if not str(ann.get("provenance") or "").strip():
            findings.append(_err("missing_provenance", "annotation provenance is missing", annotation_id=ann["id"]))
        review = ann.get("review_status")
        if review not in REVIEW:
            findings.append(_err("invalid_structure", "review_status is missing or unknown", annotation_id=ann["id"]))
        elif review != "accepted":
            findings.append(_err("unreviewed", "annotation is not accepted", annotation_id=ann["id"], review_status=review))
        bbox = ann.get("bbox")
        if not isinstance(bbox, list) or len(bbox) != 4 or not all(isinstance(v, (int, float)) for v in bbox):
            findings.append(_err("invalid_box", "bbox must be four numbers", annotation_id=ann["id"]))
            continue
        x, y, w, h = bbox
        if w <= 0 or h <= 0 or x < 0 or y < 0:
            findings.append(_err("invalid_box", "bbox origin must be non-negative and size must be positive", annotation_id=ann["id"]))
        if image is not None and isinstance(image.get("width"), int) and isinstance(image.get("height"), int):
            if x + w > image["width"] + 1e-6 or y + h > image["height"] + 1e-6:
                findings.append(_err("box_outside_image", "bbox extends outside the image", annotation_id=ann["id"]))

    for image_id, image in image_by_id.items():
        if boxes_for.get(image_id, 0) == 0 and image.get("negative") is not True:
            findings.append(_err("empty_annotation", "image has no boxes and is not marked negative", image_id=image_id))
    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate candidate annotations without writing labels.")
    parser.add_argument("--annotations", type=Path, required=True)
    parser.add_argument("--images", type=Path, default=None)
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args(argv)
    if args.out is not None and "Global_Potholes_Dataset-image" in args.out.parts:
        print("refusing to write inside Global_Potholes_Dataset-image", file=sys.stderr)
        return 2
    report: dict = {"annotations": str(args.annotations), "fixture_note": "findings describe the file that was passed in"}
    try:
        doc = json.loads(args.annotations.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        report["findings"] = [_err("invalid_json", str(exc.__class__.__name__))]
        _emit(report, args.out)
        return 2
    report["findings"] = validate_document(doc, args.images)
    report["ok"] = not report["findings"]
    _emit(report, args.out)
    return 0 if report["ok"] else 2


def _emit(report: dict, out: Path | None) -> None:
    text = json.dumps(report, indent=2)
    if out is not None:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text + "\n", encoding="utf-8")
    else:
        sys.stdout.write(text + "\n")


if __name__ == "__main__":
    sys.exit(main())
