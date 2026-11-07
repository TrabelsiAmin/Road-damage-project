#!/usr/bin/env python3
"""Write a deterministic ~200-image eval PLAN. Does not copy, move, or label images.

The manifest lists paths and says labels are required before any mAP.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
from pathlib import Path

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--images", type=Path)
    ap.add_argument("--names-file", type=Path, help="one image path per line; does not open the files")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--seed", type=int, default=20261105)
    args = ap.parse_args()
    if args.names_file:
        files = [Path(line.strip()) for line in args.names_file.read_text().splitlines() if line.strip()]
        files = [p for p in files if p.suffix.lower() in IMAGE_EXT]
    elif args.images and args.images.is_dir():
        files = sorted(p for p in args.images.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXT)
    else:
        print("provide --images or --names-file")
        return 2
    rng = random.Random(args.seed)
    pick = files if len(files) <= args.n else rng.sample(files, args.n)
    pick = sorted(pick, key=lambda p: p.name)
    # Stable split proposal: 70/15/15 by hash, not by copying files.
    splits = {"train": [], "val": [], "test": []}
    for p in pick:
        bucket = int(hashlib.sha256(p.name.encode()).hexdigest()[:8], 16) % 100
        if bucket < 70:
            split = "train"
        elif bucket < 85:
            split = "val"
        else:
            split = "test"
        splits[split].append(p.name)
    doc = {
        "status": "PLAN_ONLY",
        "tag": "NOT VERIFIED",
        "purpose": "Protocol for a future labeled eval. These rows are not labels and must not be used as ground truth.",
        "seed": args.seed,
        "requested_n": args.n,
        "listed_n": len(pick),
        "source_image_count": len(files),
        "images_dir": str(args.images),
        "split_counts": {k: len(v) for k, v in splits.items()},
        "splits": splits,
        "rules": [
            "Do not move or delete images.",
            "Do not invent boxes.",
            "Annotate in YOLO format (class cx cy w h, normalized) beside this plan, in a new labels directory.",
            "Tune thresholds only on val. Report mAP once on test.",
            "Class ids must be declared in a names file before scores are computed.",
            "Do not score train images as the test set.",
        ],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(doc, indent=2))
    print(f"wrote {args.out} n={len(pick)} splits={doc['split_counts']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
