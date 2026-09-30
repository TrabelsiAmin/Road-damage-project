"""Compare two evaluation JSON reports produced by src.evaluate.

Use this after a baseline run and a fine-tune run. Does not invent numbers.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


SMALL_DAMAGE = ("D00", "D10", "D20", "D40")


def _load(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if data.get("status") != "OK" or not data.get("metrics"):
        raise SystemExit(f"{path}: evaluation did not complete (status={data.get('status')})")
    return data


def compare(baseline: Path, finetuned: Path, output: Path) -> dict[str, Any]:
    a = _load(baseline)
    b = _load(finetuned)
    ma, mb = a["metrics"], b["metrics"]

    def delta(key: str) -> dict[str, Any]:
        va, vb = ma.get(key), mb.get(key)
        if va is None or vb is None:
            return {"baseline": va, "finetuned": vb, "delta": None}
        return {"baseline": va, "finetuned": vb, "delta": vb - va}

    per_a = ma.get("per_class_AP") or {}
    per_b = mb.get("per_class_AP") or {}
    per_class = {}
    for k in sorted(set(per_a) | set(per_b)):
        va, vb = per_a.get(k), per_b.get(k)
        per_class[k] = {
            "baseline": va,
            "finetuned": vb,
            "delta": None if va is None or vb is None else vb - va,
        }

    small = {k: per_class[k] for k in SMALL_DAMAGE if k in per_class}
    report = {
        "baseline_file": str(baseline),
        "finetuned_file": str(finetuned),
        "overall": {
            "precision": delta("precision"),
            "recall": delta("recall"),
            "mAP50": delta("mAP50"),
            "mAP50-95": delta("mAP50-95"),
        },
        "per_class_AP": per_class,
        "small_damage_classes": small,
        "note": (
            "A higher global mAP is not sufficient. Inspect small_damage_classes "
            "(D00/D10/D20/D40) before selecting a deployment model."
        ),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--finetuned", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("reports/compare.json"))
    args = parser.parse_args()
    compare(args.baseline, args.finetuned, args.output)


if __name__ == "__main__":
    main()
