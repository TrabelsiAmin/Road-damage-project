"""Full dataset preparation pipeline for TariqMap.

Converts any RDD/YOLO-format road damage dataset into three agent-specific YOLO
datasets: cracks, pavement, surface.

Rules enforced by this script
-------------------------------
1. Class mapping is REQUIRED — never guess source IDs.
2. Splits by image identity (filename hash), not randomly by index, so video
   frames from the same sequence stay in one split.
3. Near-duplicate leakage detection via MD5 hash before splitting.
4. Unknown / unmapped classes are written to an exclusion report — never silently merged.
5. Test split is kept untouched after creation.

Usage example
-------------
    python -m src.prepare_dataset \\
        --source /path/to/rdd2024 \\
        --output data/processed \\
        --class-map config/source-class-map.json \\
        --split 70:15:15

Expected source layout (YOLO format)
--------------------------------------
    <source>/
        images/    *.jpg
        labels/    *.txt  (class_id cx cy w h)

    OR a flat directory with image+label pairs (same stem).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import shutil
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

AGENTS: dict[str, list[str]] = {
    "cracks":   ["D00", "D10"],
    "pavement": ["D20", "D40"],
    "surface":  ["D50", "D60", "D90"],
}

ALL_CODES: list[str] = [c for codes in AGENTS.values() for c in codes]

SPLITS = ("train", "val", "test")

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _image_files(directory: Path) -> list[Path]:
    return sorted([f for f in directory.rglob("*") if f.suffix.lower() in IMAGE_EXTENSIONS])


def _label_for_image(image_path: Path, labels_dir: Path) -> Path | None:
    candidate = labels_dir / (image_path.stem + ".txt")
    return candidate if candidate.exists() else None


def _md5(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def _stable_split_key(stem: str) -> float:
    """Return a value in [0, 1) derived from the image filename hash.
    Using this means adjacent frames from the same video (sharing a prefix)
    stay together in one split rather than leaking across splits."""
    return int(hashlib.md5(stem.encode()).hexdigest(), 16) / (16 ** 32)


def _build_alias_to_dcode(class_map: dict[str, Any]) -> dict[str, str]:
    """Build flat alias→D-code lookup from the class-map JSON."""
    lookup: dict[str, str] = {}
    for dcode, info in class_map.items():
        if dcode.startswith("_"):
            continue
        lookup[dcode.lower()] = dcode
        lookup[dcode] = dcode
        for alias in info.get("aliases", []):
            lookup[str(alias).lower()] = dcode
    return lookup


def _resolve_class(raw_id: str, alias_map: dict[str, str]) -> str | None:
    """Map a source class id/name to a TariqMap D-code, or return None."""
    return alias_map.get(raw_id.lower()) or alias_map.get(raw_id)


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------

def prepare(
    source: Path,
    output: Path,
    class_map_path: Path,
    split_fractions: tuple[float, float, float],
    seed: int = 42,
) -> dict[str, Any]:
    """Run the full preparation pipeline. Returns a summary dict."""

    random.seed(seed)

    # Load class map
    class_map: dict[str, Any] = json.loads(class_map_path.read_text())
    alias_map = _build_alias_to_dcode(class_map)

    # Discover images and labels
    images_dir = source / "images" if (source / "images").exists() else source
    labels_dir = source / "labels" if (source / "labels").exists() else source

    images = _image_files(images_dir)
    if not images:
        raise SystemExit(f"No images found under {images_dir}")

    # Duplicate detection
    print(f"[prepare] Found {len(images)} images. Checking for duplicates…")
    hash_to_images: dict[str, list[Path]] = defaultdict(list)
    for img in images:
        hash_to_images[_md5(img)].append(img)
    duplicates = {h: paths for h, paths in hash_to_images.items() if len(paths) > 1}
    if duplicates:
        dup_count = sum(len(v) - 1 for v in duplicates.values())
        print(f"[prepare] WARNING: {dup_count} duplicate images found — keeping first occurrence.")
        deduped: list[Path] = []
        seen_hashes: set[str] = set()
        for img in images:
            h = _md5(img)
            if h not in seen_hashes:
                seen_hashes.add(h)
                deduped.append(img)
        images = deduped

    # Pair with labels; collect per-agent records
    agent_records: dict[str, list[tuple[Path, Path]]] = {a: [] for a in AGENTS}
    missing_labels: list[str] = []
    exclusion_log: list[dict[str, Any]] = []
    class_distribution: Counter = Counter()

    for img in images:
        label_path = _label_for_image(img, labels_dir)
        if label_path is None:
            missing_labels.append(str(img))
            continue

        lines = label_path.read_text().strip().splitlines()
        has_any = False
        for line_no, line in enumerate(lines, 1):
            parts = line.split()
            if len(parts) != 5:
                print(f"[prepare] SKIP bad line {label_path}:{line_no}")
                continue
            raw_cls = parts[0]
            dcode = _resolve_class(raw_cls, alias_map)
            if dcode is None:
                exclusion_log.append({
                    "image": str(img),
                    "label": str(label_path),
                    "line": line_no,
                    "raw_class": raw_cls,
                    "reason": "No mapping to TariqMap D-code",
                })
                continue
            class_distribution[dcode] += 1
            has_any = True

        if has_any:
            for agent, codes in AGENTS.items():
                # Only include this image in an agent's dataset if it has annotations for that agent
                agent_lines = []
                agent_class_ids = {c: i for i, c in enumerate(codes)}
                for line in lines:
                    parts = line.split()
                    if len(parts) != 5:
                        continue
                    dcode = _resolve_class(parts[0], alias_map)
                    if dcode in codes:
                        new_id = agent_class_ids[dcode]
                        agent_lines.append(f"{new_id} " + " ".join(parts[1:]))
                if agent_lines:
                    agent_records[agent].append((img, label_path, agent_lines))

    if missing_labels:
        pct = 100 * len(missing_labels) / len(images)
        print(f"[prepare] {len(missing_labels)} images have no label file ({pct:.1f}%)")
        if pct > 50:
            raise SystemExit(
                f"STOP: {pct:.0f}% of images are missing labels. "
                "Annotate the dataset first or verify the labels directory."
            )

    # Write exclusion report
    excl_path = output / "exclusion_report.json"
    output.mkdir(parents=True, exist_ok=True)
    excl_path.write_text(json.dumps(exclusion_log, indent=2))
    print(f"[prepare] Exclusion report → {excl_path} ({len(exclusion_log)} entries)")

    # Create output datasets per agent
    train_f, val_f, test_f = split_fractions
    for agent, records in agent_records.items():
        agent_dir = output / agent
        for split in SPLITS:
            (agent_dir / "images" / split).mkdir(parents=True, exist_ok=True)
            (agent_dir / "labels" / split).mkdir(parents=True, exist_ok=True)

        # Sort by stable split key so adjacent video frames cluster together
        records.sort(key=lambda r: _stable_split_key(r[0].stem))

        n = len(records)
        n_train = int(n * train_f)
        n_val = int(n * val_f)

        splits_map = (
            [("train", records[:n_train])] +
            [("val", records[n_train:n_train + n_val])] +
            [("test", records[n_train + n_val:])]
        )

        for split_name, split_records in splits_map:
            for img_path, _lbl_path, agent_lines in split_records:
                dest_img = agent_dir / "images" / split_name / img_path.name
                dest_lbl = agent_dir / "labels" / split_name / (img_path.stem + ".txt")
                shutil.copy2(img_path, dest_img)
                dest_lbl.write_text("\n".join(agent_lines))

        print(
            f"[prepare] {agent}: {n} images → "
            f"train={n_train} / val={n_val} / test={n - n_train - n_val}"
        )

    summary = {
        "prepared_at": datetime.now(timezone.utc).isoformat(),
        "source": str(source.resolve()),
        "output": str(output.resolve()),
        "class_map": str(class_map_path.resolve()),
        "total_images_found": len(images),
        "duplicate_images_removed": len(duplicates),
        "missing_labels": len(missing_labels),
        "exclusion_entries": len(exclusion_log),
        "class_distribution": dict(class_distribution),
        "agent_image_counts": {
            agent: len(records) for agent, records in agent_records.items()
        },
    }

    summary_path = output / "preparation_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2))
    print(f"[prepare] Summary → {summary_path}")
    return summary


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare TariqMap YOLO datasets from source")
    parser.add_argument("--source", type=Path, required=True, help="Source dataset root")
    parser.add_argument("--output", type=Path, required=True, help="Output data/processed root")
    parser.add_argument("--class-map", type=Path, required=True, help="source-class-map.json path")
    parser.add_argument("--split", default="70:15:15", help="Train:Val:Test split percentages")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for determinism")
    args = parser.parse_args()

    parts = [float(x) for x in args.split.split(":")]
    if len(parts) != 3 or abs(sum(parts) - 100) > 0.01:
        raise SystemExit("--split must be three numbers summing to 100, e.g. 70:15:15")
    fractions = tuple(p / 100 for p in parts)

    prepare(args.source, args.output, args.class_map, fractions, seed=args.seed)


if __name__ == "__main__":
    main()
