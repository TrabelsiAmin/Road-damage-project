"""Export trained YOLOv8 weights to TFLite for mobile deployment.

Exports float32, float16, and int8 TFLite variants, computes SHA-256
checksums, and updates the model-bundles.json manifest.

Usage:
    python -m src.export \\
        --weights runs/cracks/weights/best.pt \\
        --agent cracks \\
        --output ../app/assets/models \\
        --precision float16
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

# Ultralytics is imported inside export_tflite so missing-weights checks
# do not require a GPU training stack.

# ---------------------------------------------------------------------------
# Supported precisions (export ladder: float32 → float16 → int8)
# ---------------------------------------------------------------------------

PRECISIONS = ("float32", "float16", "int8")

AGENTS_CLASSES: dict[str, list[str]] = {
    "cracks":   ["D00", "D10"],
    "pavement": ["D20", "D40"],
    "surface":  ["D50", "D60", "D90"],
}


# ---------------------------------------------------------------------------
# SHA-256 checksum
# ---------------------------------------------------------------------------

def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def export_tflite(
    weights_path: Path,
    agent: str,
    output_dir: Path,
    precision: str = "float16",
    imgsz: int = 640,
) -> Path:
    """Export a YOLOv8 .pt model to TFLite and return the output file path."""
    if not weights_path.exists():
        raise SystemExit(
            f"NOT_RUN: weights not found at {weights_path}. "
            "Train a real YOLOv8 checkpoint before export. "
            "Do not bundle a placeholder .tflite."
        )
    try:
        from ultralytics import YOLO
    except ImportError as exc:
        raise SystemExit(
            "NOT_RUN: ultralytics is not installed. pip install -r requirements.txt"
        ) from exc

    output_dir.mkdir(parents=True, exist_ok=True)

    model = YOLO(str(weights_path))

    # Ultralytics export kwargs for TFLite
    export_kwargs: dict = {
        "format": "tflite",
        "imgsz": imgsz,
        "simplify": True,
    }
    if precision == "float16":
        export_kwargs["half"] = True
    elif precision == "int8":
        export_kwargs["int8"] = True
        # int8 requires calibration data (representative dataset)
        # Without it, Ultralytics will use synthetic calibration — note this limitation.
        print(f"[export] WARNING: int8 export without calibration data — accuracy may degrade.")

    exported_path_str: str = model.export(**export_kwargs)
    exported_path = Path(exported_path_str)

    if not exported_path.exists():
        raise FileNotFoundError(f"Export produced no file at {exported_path}")

    # Copy to output dir with canonical name
    dest_name = f"{agent}.tflite"
    dest_path = output_dir / dest_name
    shutil.copy2(exported_path, dest_path)
    print(f"[export] Exported → {dest_path} ({dest_path.stat().st_size / 1024 / 1024:.2f} MB)")

    return dest_path


# ---------------------------------------------------------------------------
# Manifest update
# ---------------------------------------------------------------------------

def _update_manifest(
    manifest_path: Path,
    agent: str,
    model_file: str,
    checksum: str,
    precision: str,
    imgsz: int,
    model_size_bytes: int,
    training_source: str,
) -> None:
    manifest = json.loads(manifest_path.read_text())

    for agent_entry in manifest.get("agents", []):
        if agent_entry["name"] == agent:
            agent_entry.update({
                "format": "tflite",
                "file": model_file,
                "sha256": checksum,
                "precision": precision,
                "input_width": imgsz,
                "input_height": imgsz,
                "model_size_bytes": model_size_bytes,
                "exported_at_utc": datetime.now(timezone.utc).isoformat(),
                "training_dataset_source": training_source,
                "classes": AGENTS_CLASSES.get(agent, []),
            })
            break

    manifest_path.write_text(json.dumps(manifest, indent=2))
    print(f"[export] Manifest updated → {manifest_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Export TariqMap YOLOv8 model to TFLite")
    parser.add_argument("--weights", type=Path, required=True, help="Path to best.pt")
    parser.add_argument("--agent", required=True, choices=list(AGENTS_CLASSES), help="Agent name")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).parents[2] / "app" / "assets" / "models",
        help="Output directory (default: app/assets/models)",
    )
    parser.add_argument(
        "--precision",
        default="float16",
        choices=PRECISIONS,
        help="Export precision ladder",
    )
    parser.add_argument("--imgsz", type=int, default=640, help="Input image size")
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path(__file__).parents[2] / "app" / "assets" / "models" / "model-bundles.json",
        help="model-bundles.json to update after export",
    )
    parser.add_argument(
        "--training-source",
        default="RDD2024",
        help="Dataset used for training (for model card)",
    )
    args = parser.parse_args()

    print(f"\n[export] Agent: {args.agent}  |  Precision: {args.precision}  |  imgsz: {args.imgsz}")

    dest = export_tflite(
        weights_path=args.weights,
        agent=args.agent,
        output_dir=args.output,
        precision=args.precision,
        imgsz=args.imgsz,
    )

    checksum = _sha256(dest)
    print(f"[export] SHA-256: {checksum}")

    if args.manifest.exists():
        _update_manifest(
            manifest_path=args.manifest,
            agent=args.agent,
            model_file=dest.name,
            checksum=checksum,
            precision=args.precision,
            imgsz=args.imgsz,
            model_size_bytes=dest.stat().st_size,
            training_source=args.training_source,
        )
    else:
        print(f"[export] WARNING: manifest not found at {args.manifest} — skipping update")

    print(f"\n[export] Done. File: {dest}")
    print(f"[export] SHA-256: {checksum}")
    print(f"[export] Update model-bundles.json sha256 field if not auto-updated.")


if __name__ == "__main__":
    main()
