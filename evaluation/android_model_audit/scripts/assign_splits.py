#!/usr/bin/env python3
"""Assign duplicate-aware splits from in-memory records.

Groups that share a content hash stay in one split. The assignment is a pure
function of the records and the seed. This module does not read or write the
Global_Potholes images, and it does not create a split of that dataset.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import defaultdict
from pathlib import Path


def assign_splits(records: list[dict], seed: int, ratios: tuple[float, float, float] = (0.7, 0.15, 0.15)) -> dict:
    if len(ratios) != 3 or abs(sum(ratios) - 1.0) > 1e-9:
        raise ValueError("ratios must be three numbers that sum to 1")
    groups: dict[str, list[str]] = defaultdict(list)
    for record in records:
        groups[str(record["content_hash"])].append(str(record["id"]))
    assigned = {"train": [], "val": [], "test": []}
    for key in sorted(groups):
        split = _bucket(seed, key, ratios)
        assigned[split].extend(sorted(groups[key]))
    for name in assigned:
        assigned[name] = sorted(assigned[name])
    return {
        "seed": seed,
        "ratios": list(ratios),
        "splits": assigned,
        "group_count": len(groups),
        "class_distribution": None,
        "note": "Class counts are omitted until annotations are verified.",
    }


def class_distribution(records: list[dict], verified: bool) -> dict | None:
    if not verified:
        return None
    counts: dict[str, int] = defaultdict(int)
    for record in records:
        name = record.get("category_name")
        if name:
            counts[str(name)] += 1
    return dict(sorted(counts.items()))


def _bucket(seed: int, key: str, ratios: tuple[float, float, float]) -> str:
    digest = hashlib.sha256(f"{seed}|{key}".encode("utf-8")).hexdigest()
    unit = int(digest[:8], 16) / 0xFFFFFFFF
    if unit < ratios[0]:
        return "train"
    if unit < ratios[0] + ratios[1]:
        return "val"
    return "test"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Duplicate-aware split for synthetic records only.")
    parser.add_argument("--records", type=Path, required=True)
    parser.add_argument("--seed", type=int, required=True)
    args = parser.parse_args(argv)
    if "Global_Potholes_Dataset-image" in args.records.parts or "Global_Potholes_Dataset-image" in str(args.records):
        print("refusing to split Global_Potholes_Dataset-image; ground truth is unavailable", file=sys.stderr)
        return 2
    records = json.loads(args.records.read_text(encoding="utf-8"))
    report = assign_splits(records, args.seed)
    json.dump(report, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
