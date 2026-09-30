"""Select the WP3 checkpoint from measured eval JSON only.

Criteria (highest first):
    1. D40 AP50 (potholes; many small boxes)
    2. D20 AP50
    3. mAP50
    4. smaller checkpoint size as a tie-break

Does not invent metrics. Missing/NOT_RUN files → status NOT_RUN and no copy.

Usage:
    python -m evaluation.select_wp3_best \\
        --candidate wp3_baseline reports/wp3/baseline/metrics.json runs/wp3_baseline/weights/best.pt \\
        --candidate wp3_s640 reports/wp3/wp3_expB_s640/metrics.json runs/wp3_expB_s640/weights/best.pt \\
        --dest reports/wp3/artifacts/best.pt
"""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path
from typing import Any


def _load(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return None


def _num(value: Any) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _rank_key(metrics: dict[str, Any], size_bytes: int | None) -> tuple[float, float, float, float] | None:
    per = metrics.get("per_class") or {}
    d40 = _num((per.get("D40") or {}).get("AP50"))
    d20 = _num((per.get("D20") or {}).get("AP50"))
    m50 = _num(metrics.get("mAP50"))
    if d40 is None or d20 is None or m50 is None:
        return None
    size_term = 0.0 if size_bytes is None else -float(size_bytes)
    return (d40, d20, m50, size_term)


def select_best(
    candidates: list[dict[str, Any]],
    dest: Path,
) -> dict[str, Any]:
    """`candidates` items: name, metrics_path, weights_path."""
    ranked: list[dict[str, Any]] = []
    reasons: list[str] = []
    for item in candidates:
        name = str(item.get("name"))
        metrics_path = Path(item["metrics_path"])
        weights_path = Path(item["weights_path"])
        payload = _load(metrics_path)
        rec: dict[str, Any] = {
            "name": name,
            "metrics_path": str(metrics_path),
            "weights_path": str(weights_path),
            "status": "NOT_RUN",
            "key": None,
        }
        if payload is None:
            reasons.append(f"{name}: metrics JSON missing or invalid ({metrics_path})")
            ranked.append(rec)
            continue
        if payload.get("status") != "OK" or not payload.get("metrics"):
            reasons.append(f"{name}: status={payload.get('status')}; metrics not available")
            ranked.append(rec)
            continue
        if not weights_path.is_file():
            reasons.append(f"{name}: weights missing ({weights_path})")
            ranked.append(rec)
            continue
        key = _rank_key(payload["metrics"], weights_path.stat().st_size)
        if key is None:
            reasons.append(f"{name}: D20/D40 AP50 or mAP50 missing — cannot rank")
            ranked.append(rec)
            continue
        rec["status"] = "OK"
        rec["key"] = {
            "D40_AP50": key[0],
            "D20_AP50": key[1],
            "mAP50": key[2],
            "neg_size_bytes": key[3],
        }
        rec["size_bytes"] = weights_path.stat().st_size
        ranked.append(rec)

    ok = [r for r in ranked if r["status"] == "OK" and r["key"] is not None]
    ok.sort(
        key=lambda r: (
            r["key"]["D40_AP50"],
            r["key"]["D20_AP50"],
            r["key"]["mAP50"],
            r["key"]["neg_size_bytes"],
        ),
        reverse=True,
    )

    report: dict[str, Any] = {
        "status": "NOT_RUN",
        "wp": "WP3",
        "criteria": [
            "D40 AP50 (potholes / small objects)",
            "D20 AP50",
            "mAP50",
            "smaller checkpoint as tie-break",
        ],
        "candidates": ranked,
        "selected": None,
        "dest": str(dest),
        "reasons": reasons,
        "note": (
            "Do not auto-select the largest backbone. "
            "A higher global mAP alone is not enough. "
            "Training NOT YET EXECUTED if status is NOT_RUN."
        ),
    }

    if not ok:
        dest.parent.mkdir(parents=True, exist_ok=True)
        (dest.parent / "selection.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return report

    winner = ok[0]
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(winner["weights_path"], dest)
    report["status"] = "OK"
    report["selected"] = winner["name"]
    report["copied_from"] = winner["weights_path"]
    report["copied_bytes"] = dest.stat().st_size
    (dest.parent / "selection.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Select WP3 best.pt from measured JSON")
    parser.add_argument(
        "--candidate",
        nargs=3,
        action="append",
        metavar=("NAME", "METRICS_JSON", "WEIGHTS"),
        required=True,
    )
    parser.add_argument("--dest", type=Path, default=Path("reports/wp3/artifacts/best.pt"))
    args = parser.parse_args()
    candidates = [
        {"name": name, "metrics_path": Path(metrics), "weights_path": Path(weights)}
        for name, metrics, weights in args.candidate
    ]
    select_best(candidates, args.dest)


if __name__ == "__main__":
    main()
