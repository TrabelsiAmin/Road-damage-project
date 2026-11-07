#!/usr/bin/env python3
"""Readiness gate for road-damage model evaluation.

This script may load the existing TFLite file and report tensor shapes.
It does not calculate precision, recall, F1, mAP, or accuracy.

It exits 2 with status NOT EVALUABLE unless both of these are true:
- a label directory contains parseable YOLO, COCO, VOC, or CSV annotations
- a mapping file explicitly says mapping_status is VERIFIED

A class-name list in code is not a verified mapping. source-class-map.json
is an alias policy, not proof that model channel order matches those names.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Existing legacy contract. Not a claim that the names are scientifically proven.
LEGACY_INPUT = [1, 640, 640, 3]
LEGACY_OUTPUT = [1, 8, 8400]
ROADSENSE_INPUT = [1, 3, 640, 640]
ROADSENSE_OUTPUT = [1, 9, 8400]

_IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}


def _tensor_shapes(model_path: Path) -> dict:
    try:
        from ai_edge_litert.interpreter import Interpreter
    except ImportError as exc:
        return {"loaded": False, "reason": f"interpreter import failed: {exc.__class__.__name__}"}
    interpreter = Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    inputs = interpreter.get_input_details()
    outputs = interpreter.get_output_details()
    return {
        "loaded": True,
        "input_shape": [int(x) for x in inputs[0]["shape"]],
        "output_shape": [int(x) for x in outputs[0]["shape"]],
        "input_dtype": str(inputs[0]["dtype"]),
        "output_dtype": str(outputs[0]["dtype"]),
    }


def _count_labels(dataset: Path) -> dict:
    counts = {"yolo_txt": 0, "coco_or_json": 0, "voc_xml": 0, "csv": 0, "images": 0}
    if not dataset.exists():
        counts["dataset_missing"] = True
        return counts
    for path in dataset.rglob("*"):
        if not path.is_file():
            continue
        suffix = path.suffix.lower()
        if suffix in _IMAGE_SUFFIXES:
            counts["images"] += 1
        elif suffix == ".txt" and _looks_like_yolo(path):
            counts["yolo_txt"] += 1
        elif suffix == ".xml" and "<annotation" in path.read_text(encoding="utf-8", errors="ignore")[:400]:
            counts["voc_xml"] += 1
        elif suffix == ".csv":
            counts["csv"] += 1
        elif suffix == ".json" and path.name not in {"global_potholes_manifest.json"}:
            text = path.read_text(encoding="utf-8", errors="ignore")[:400]
            if "annotations" in text or "categories" in text or "shapes" in text:
                counts["coco_or_json"] += 1
    counts["label_files"] = counts["yolo_txt"] + counts["coco_or_json"] + counts["voc_xml"] + counts["csv"]
    return counts


def _looks_like_yolo(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return False
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 5:
            try:
                int(parts[0])
                [float(x) for x in parts[1:]]
                return True
            except ValueError:
                continue
    return False


def _mapping_verified(path: Path | None) -> tuple[bool, str]:
    if path is None:
        return False, "no mapping file was provided"
    if not path.is_file():
        return False, f"mapping file does not exist: {path}"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return False, "mapping file is not JSON"
    if payload.get("mapping_status") != "VERIFIED":
        return False, "mapping_status is not VERIFIED"
    evidence = payload.get("evidence")
    if not isinstance(evidence, list) or not evidence:
        return False, "VERIFIED mapping requires a non-empty evidence list"
    return True, "mapping file is marked VERIFIED"


SCHEMA_ID = "tariqmap-annotations-1"


def _candidate_annotation_file(path: Path) -> dict | None:
    """Return a parsed candidate document, or None if this is not one."""
    if path.suffix.lower() != ".json" or not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    info = payload.get("info") if isinstance(payload.get("info"), dict) else {}
    if info.get("annotation_schema") == SCHEMA_ID:
        return payload
    if {"images", "annotations", "categories"} <= set(payload):
        return payload
    return None


def assess(model: Path, dataset: Path, mapping: Path | None, annotations: Path | None = None) -> dict:
    shapes = _tensor_shapes(model) if model.is_file() else {"loaded": False, "reason": "model file missing"}
    labels = _count_labels(dataset)
    candidate = _candidate_annotation_file(annotations) if annotations is not None else None
    if candidate is not None:
        labels["candidate_schema"] = (candidate.get("info") or {}).get("annotation_schema")
        labels["coco_or_json"] = labels.get("coco_or_json", 0) + 1
        labels["label_files"] = labels.get("label_files", 0) + 1
        pending = [
            cat.get("id")
            for cat in candidate.get("categories") or []
            if isinstance(cat, dict) and cat.get("definition_status") != "confirmed"
        ]
        labels["pending_categories"] = pending
    mapping_ok, mapping_reason = _mapping_verified(mapping)
    reasons = []
    if labels.get("label_files", 0) == 0:
        reasons.append("no YOLO, COCO, VOC, or CSV ground-truth files were found")
    if candidate is not None and labels.get("pending_categories"):
        reasons.append("annotation categories are still pending confirmation")
    if not mapping_ok:
        reasons.append(mapping_reason)
    expected = LEGACY_OUTPUT if "roadsense" not in model.name else ROADSENSE_OUTPUT
    expected_in = LEGACY_INPUT if "roadsense" not in model.name else ROADSENSE_INPUT
    if shapes.get("loaded"):
        if shapes["input_shape"] != expected_in or shapes["output_shape"] != expected:
            reasons.append(
                f"tensor shapes {shapes['input_shape']} -> {shapes['output_shape']} "
                f"do not match the existing contract {expected_in} -> {expected}"
            )
    # Scores stay null. This script has no metric implementation.
    if not reasons:
        reasons.append(
            "labels and a VERIFIED mapping were supplied, but this script "
            "does not calculate scores"
        )
    status = "NOT EVALUABLE"
    return {
        "status": status,
        "metrics": None,
        "reasons": reasons,
        "model": str(model),
        "tensor_shapes": shapes,
        "expected_contract": {"input": expected_in, "output": expected, "preprocess": "stretch_to_640"},
        "labels": labels,
        "mapping_verified": mapping_ok,
        "note": "Detection scores are not computed.",
    }


def main(argv: list[str] | None = None) -> int:
    repo = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description="Refuse model metrics until labels and a verified mapping exist.")
    parser.add_argument("--model", type=Path, default=repo / "app/assets/models/road_damage.tflite")
    parser.add_argument("--dataset", type=Path, default=repo / "Global_Potholes_Dataset-image")
    parser.add_argument("--mapping", type=Path, default=None)
    parser.add_argument(
        "--annotations",
        type=Path,
        default=None,
        help="Optional COCO-like file. Recognized as a candidate only. Scores stay null until mapping is verified.",
    )
    args = parser.parse_args(argv)
    report = assess(args.model, args.dataset, args.mapping, args.annotations)
    json.dump(report, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 2 if report["status"] == "NOT EVALUABLE" or report["metrics"] is None else 0


if __name__ == "__main__":
    sys.exit(main())
