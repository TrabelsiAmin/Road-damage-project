"""WP3 test-split evaluation. Writes JSON; never invents mAP.

Usage:
    python -m src.eval_wp3 --weights runs/wp3_baseline/weights/best.pt \\
        --data config/pavement.yaml --split test \\
        --output reports/wp3/baseline/metrics.json
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

WP3_NAMES = {0: "D20", 1: "D40"}


def _f(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _f1(precision: float | None, recall: float | None) -> float | None:
    if precision is None or recall is None:
        return None
    denom = precision + recall
    if denom <= 0:
        return None
    return 2.0 * precision * recall / denom


def _per_class(box: Any, names: dict) -> dict[str, Any]:
    out: dict[str, Any] = {}
    p = getattr(box, "p", None)
    r = getattr(box, "r", None)
    ap50 = getattr(box, "ap50", None)
    ap = getattr(box, "ap", None)
    maps = getattr(box, "maps", None)

    def _idx(arr: Any, i: int) -> float | None:
        if arr is None:
            return None
        try:
            return _f(list(arr)[i])
        except (TypeError, IndexError, ValueError):
            return None

    for idx, label in names.items():
        entry = {
            "precision": _idx(p, idx),
            "recall": _idx(r, idx),
            "AP50": _idx(ap50, idx),
            "AP50-95": _idx(ap, idx) if ap is not None else _idx(maps, idx),
        }
        entry["F1"] = _f1(entry["precision"], entry["recall"])
        out[str(label)] = entry
    return out


def serialize_wp3(result: Any) -> dict[str, Any]:
    names = dict(WP3_NAMES)
    raw_names = getattr(result, "names", None) or {}
    if raw_names:
        names = {int(k): str(v) for k, v in dict(raw_names).items()}
    metrics: dict[str, Any] = {
        "precision": None,
        "recall": None,
        "mAP50": None,
        "mAP50-95": None,
        "F1": None,
        "per_class": {},
        "speed_ms": None,
    }
    box = getattr(result, "box", None)
    if box is not None:
        metrics["precision"] = _f(getattr(box, "mp", None))
        metrics["recall"] = _f(getattr(box, "mr", None))
        metrics["mAP50"] = _f(getattr(box, "map50", None))
        metrics["mAP50-95"] = _f(getattr(box, "map", None))
        metrics["F1"] = _f1(metrics["precision"], metrics["recall"])
        metrics["per_class"] = _per_class(box, names)
    if hasattr(result, "results_dict") and isinstance(result.results_dict, dict):
        metrics["ultralytics_results_dict"] = {
            str(k): _f(v) for k, v in result.results_dict.items()
        }
    speed = getattr(result, "speed", None)
    if isinstance(speed, dict):
        metrics["speed_ms"] = {str(k): _f(v) for k, v in speed.items()}
    return metrics


def evaluate_wp3(
    weights: Path,
    data: Path,
    split: str,
    imgsz: int,
    output: Path,
    run_name: str = "baseline",
) -> dict[str, Any]:
    report: dict[str, Any] = {
        "status": "NOT_RUN",
        "wp": "WP3",
        "agent": "pavement",
        "classes": ["D20", "D40"],
        "run_name": run_name,
        "evaluated_at_utc": datetime.now(timezone.utc).isoformat(),
        "weights": str(weights),
        "data": str(data),
        "split": split,
        "imgsz": imgsz,
        "metrics": None,
        "reason": None,
        "artifacts": {},
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    if not weights.exists():
        report["reason"] = (
            f"Weights not found: {weights}. Train WP3 on Colab first. "
            "No placeholder Precision/Recall/mAP is written."
        )
        output.write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return report
    if not data.exists():
        report["reason"] = f"Data YAML not found: {data}"
        output.write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return report
    try:
        from ultralytics import YOLO
    except ImportError:
        report["reason"] = "ultralytics is not installed"
        output.write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return report

    model = YOLO(str(weights))
    result = model.val(data=str(data), split=split, imgsz=imgsz, plots=True)
    report["status"] = "OK"
    report["metrics"] = serialize_wp3(result)
    save_dir = getattr(result, "save_dir", None)
    report["artifacts"] = {
        "ultralytics_save_dir": str(save_dir) if save_dir else None,
        "confusion_matrix": "confusion_matrix.png in the val run directory if plots=True",
        "pr_curves": "PRCurve*.png in the val run directory if plots=True",
    }
    output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate WP3 pavement weights on a fixed split")
    parser.add_argument("--weights", type=Path, required=True)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--split", default="test", choices=("val", "test"))
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--run-name", default="baseline")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("reports/wp3/baseline/metrics.json"),
    )
    args = parser.parse_args()
    evaluate_wp3(args.weights, args.data, args.split, args.imgsz, args.output, args.run_name)


if __name__ == "__main__":
    main()
