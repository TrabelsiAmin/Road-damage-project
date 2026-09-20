"""Compare two WP3 evaluation JSON files.

Prints a markdown table:

    Metric | Baseline | Improved | Delta

Does **not** declare a model better unless both files have status OK and
numeric metrics. Missing/NOT_RUN files produce status NOT_RUN.

Usage:
    python evaluation/compare_wp3_models.py \\
        --baseline reports/wp3/baseline/metrics.json \\
        --improved reports/wp3/final/metrics.json \\
        --output reports/wp3/compare.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

METRICS_ORDER = (
    "precision",
    "recall",
    "F1",
    "mAP50",
    "mAP50-95",
)

PER_CLASS_KEYS = ("precision", "recall", "F1", "AP50", "AP50-95")


def _load_raw(path: Path) -> dict[str, Any] | None:
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


def _cell(value: float | None) -> str:
    if value is None:
        return "NOT_RUN"
    return f"{value:.4f}"


def compare(baseline: Path, improved: Path, output: Path) -> dict[str, Any]:
    a = _load_raw(baseline)
    b = _load_raw(improved)
    rows: list[dict[str, Any]] = []
    status = "OK"
    reasons: list[str] = []

    if a is None:
        status = "NOT_RUN"
        reasons.append(f"baseline file missing or invalid: {baseline}")
    elif a.get("status") != "OK" or not a.get("metrics"):
        status = "NOT_RUN"
        reasons.append(f"baseline status={a.get('status') if a else None}; metrics not available")
    if b is None:
        status = "NOT_RUN"
        reasons.append(f"improved file missing or invalid: {improved}")
    elif b.get("status") != "OK" or not b.get("metrics"):
        status = "NOT_RUN"
        reasons.append(f"improved status={b.get('status') if b else None}; metrics not available")

    ma = (a or {}).get("metrics") or {}
    mb = (b or {}).get("metrics") or {}

    def add_row(metric: str, va: Any, vb: Any) -> None:
        na, nb = _num(va), _num(vb)
        delta = None if na is None or nb is None else nb - na
        rows.append(
            {
                "metric": metric,
                "baseline": na,
                "improved": nb,
                "delta": delta,
            }
        )

    for key in METRICS_ORDER:
        add_row(key, ma.get(key), mb.get(key))

    per_a = ma.get("per_class") or {}
    per_b = mb.get("per_class") or {}
    for cls in ("D20", "D40"):
        ca, cb = per_a.get(cls) or {}, per_b.get(cls) or {}
        for key in PER_CLASS_KEYS:
            add_row(f"{cls}_{key}", ca.get(key), cb.get(key))

    declare_better = False
    selection_note = (
        "Do not auto-select the largest model. Prefer D20 + D40 AP, small-object "
        "behaviour, then size/latency. A higher global mAP alone is not enough."
    )
    if status == "OK":
        d40 = next((r for r in rows if r["metric"] == "D40_AP50"), None)
        d20 = next((r for r in rows if r["metric"] == "D20_AP50"), None)
        map50 = next((r for r in rows if r["metric"] == "mAP50"), None)
        gains = []
        for row in (d20, d40, map50):
            if row and row["delta"] is not None:
                gains.append(row["delta"])
        if gains and all(g > 0 for g in gains):
            declare_better = True
            selection_note = (
                "Improved run has higher D20 AP50, D40 AP50, and mAP50 than baseline. "
                "Still check small-object bins and on-device latency before deploy."
            )
        else:
            selection_note = (
                "Numbers exist but do not uniformly improve D20 AP50, D40 AP50, and mAP50. "
                "Do not call the second model better without inspecting small objects and latency."
            )

    md_lines = [
        "| Metric | Baseline | Improved | Delta |",
        "| --- | ---: | ---: | ---: |",
    ]
    for row in rows:
        delta_s = "NOT_RUN" if row["delta"] is None else f"{row['delta']:+.4f}"
        md_lines.append(
            f"| {row['metric']} | {_cell(row['baseline'])} | {_cell(row['improved'])} | {delta_s} |"
        )
    markdown = "\n".join(md_lines)

    report = {
        "status": status,
        "wp": "WP3",
        "baseline_file": str(baseline),
        "improved_file": str(improved),
        "declare_better": declare_better,
        "reasons": reasons,
        "rows": rows,
        "markdown_table": markdown,
        "selection_note": selection_note,
        "note": (
            "Training NOT YET EXECUTED if status is NOT_RUN. "
            "Empty cells are not zeros."
        ),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2))
    print(markdown)
    print(json.dumps({k: report[k] for k in ("status", "declare_better", "reasons", "selection_note")}, indent=2))
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare WP3 baseline vs improved eval JSON")
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--improved", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("reports/wp3/compare.json"))
    args = parser.parse_args()
    compare(args.baseline, args.improved, args.output)


if __name__ == "__main__":
    main()
