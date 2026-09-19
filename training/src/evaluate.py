"""Evaluate a trained Ultralytics YOLO checkpoint on a labeled split.

Does not invent metrics. If weights or data are missing, exits with
status NOT_RUN and writes a placeholder report.

Usage:
    python -m src.evaluate --weights runs/cracks/weights/best.pt --data config/cracks.yaml --split test
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _serialize_metrics(result: Any) -> dict[str, Any]:
    out: dict[str, Any] = {}
    box = getattr(result, "box", None)
    if box is not None:
        out["precision"] = _f(getattr(box, "mp", None))
        out["recall"] = _f(getattr(box, "mr", None))
        out["mAP50"] = _f(getattr(box, "map50", None))
        out["mAP50-95"] = _f(getattr(box, "map", None))
        maps = getattr(box, "maps", None)
        names = getattr(result, "names", {}) or {}
        if maps is not None:
            per_class = {}
            for idx, value in enumerate(list(maps)):
                label = names.get(idx, str(idx))
                per_class[str(label)] = _f(value)
            out["per_class_AP"] = per_class
    if hasattr(result, "results_dict") and isinstance(result.results_dict, dict):
        out["ultralytics_results_dict"] = {
            str(k): _f(v) for k, v in result.results_dict.items()
        }
    speed = getattr(result, "speed", None)
    if isinstance(speed, dict):
        out["speed_ms"] = {str(k): _f(v) for k, v in speed.items()}
    return out


def _f(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def evaluate(
    weights: Path,
    data: Path,
    split: str,
    imgsz: int,
    output: Path,
) -> dict[str, Any]:
    report: dict[str, Any] = {
        "status": "NOT_RUN",
        "evaluated_at_utc": datetime.now(timezone.utc).isoformat(),
        "weights": str(weights),
        "data": str(data),
        "split": split,
        "imgsz": imgsz,
        "metrics": None,
        "reason": None,
    }
    if not weights.exists():
        report["reason"] = f"Weights not found: {weights}. Train first."
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return report
    if not data.exists():
        report["reason"] = f"Data YAML not found: {data}"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return report

    try:
        from ultralytics import YOLO
    except ImportError:
        report["reason"] = "ultralytics is not installed"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return report

    model = YOLO(str(weights))
    result = model.val(data=str(data), split=split, imgsz=imgsz, plots=True)
    report["status"] = "OK"
    report["metrics"] = _serialize_metrics(result)
    report["artifacts_hint"] = {
        "confusion_matrix": "written by Ultralytics into the val run directory",
        "pr_curves": "PRCurve*.png in the val run directory",
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate YOLO weights (no invented metrics)")
    parser.add_argument("--weights", type=Path, required=True)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--split", default="test", choices=("val", "test"))
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("reports/last_eval.json"),
    )
    args = parser.parse_args()
    evaluate(args.weights, args.data, args.split, args.imgsz, args.output)


if __name__ == "__main__":
    main()
