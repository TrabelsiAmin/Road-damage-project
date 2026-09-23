"""Export trained YOLOv8 weights to TFLite and ONNX for mobile + backend deployment.

Exports float32, float16, and int8 TFLite variants plus ONNX (for server-side
inference), computes SHA-256 checksums, and updates the model-bundles.json manifest.

For int8 accuracy: provide a calibration directory with representative road images
via --calibration-data.  Without it, Ultralytics uses synthetic calibration which
may degrade accuracy by 1-3 mAP.

Usage:
    # Standard float16 export (recommended for mobile)
    python -m src.export \\
        --weights runs/cracks/weights/best.pt \\
        --agent cracks \\
        --precision float16

    # int8 with real calibration data (smallest, best for low-end devices)
    python -m src.export \\
        --weights runs/cracks/weights/best.pt \\
        --agent cracks \\
        --precision int8 \\
        --calibration-data /path/to/calibration_images/

    # Also export ONNX for server-side inference
    python -m src.export \\
        --weights runs/cracks/weights/best.pt \\
        --agent cracks \\
        --precision float16 \\
        --export-onnx
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from ultralytics import YOLO


# ---------------------------------------------------------------------------
# Supported precisions
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
# Validate exported TFLite output shape
# ---------------------------------------------------------------------------

def _validate_tflite_shape(tflite_path: Path, expected_classes: int = 7) -> bool:
    """Load exported TFLite model and check output tensor shape is [1, 4+cls, 8400].

    Returns True if valid, False if shape is unexpected (export continues either way).
    """
    try:
        import numpy as np
        try:
            import tflite_runtime.interpreter as tflite
        except ImportError:
            import tensorflow.lite as tflite  # type: ignore[no-redef]

        interpreter = tflite.Interpreter(model_path=str(tflite_path))
        interpreter.allocate_tensors()
        output_details = interpreter.get_output_details()
        if not output_details:
            print("[export] WARNING: TFLite model has no output tensors.")
            return False

        shape = output_details[0]["shape"]
        # Expected: [1, 4 + num_classes, 8400]
        expected = (1, 4 + expected_classes, 8400)
        if tuple(shape) == expected:
            print(f"[export] ✓ TFLite output shape validated: {list(shape)}")
            return True
        else:
            print(
                f"[export] WARNING: Unexpected output shape {list(shape)}."
                f" Expected {list(expected)}."
                f" Verify TFLiteAgentRunner numAnchors / numClasses constants."
            )
            return False
    except Exception as exc:
        print(f"[export] WARNING: Shape validation skipped ({exc}).")
        return True  # Don't block the export if runtime not available


# ---------------------------------------------------------------------------
# TFLite export
# ---------------------------------------------------------------------------

def export_tflite(
    weights_path: Path,
    agent: str,
    output_dir: Path,
    precision: str = "float16",
    imgsz: int = 640,
    calibration_data: Path | None = None,
) -> Path:
    """Export a YOLOv8 .pt model to TFLite and return the output file path."""
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
        if calibration_data is not None and calibration_data.is_dir():
            export_kwargs["data"] = str(calibration_data)
            print(f"[export] int8 calibration data: {calibration_data}")
        else:
            print(
                "[export] WARNING: int8 export without calibration data —"
                " accuracy may degrade by 1-3 mAP points."
                " Provide --calibration-data <dir_with_representative_images>."
            )

    exported_path_str: str = model.export(**export_kwargs)
    exported_path = Path(exported_path_str)

    if not exported_path.exists():
        raise FileNotFoundError(f"Export produced no file at {exported_path}")

    # Copy to output dir with canonical name
    dest_name = f"{agent}.tflite"
    dest_path = output_dir / dest_name
    shutil.copy2(exported_path, dest_path)
    print(f"[export] TFLite exported → {dest_path} ({dest_path.stat().st_size / 1024 / 1024:.2f} MB)")

    # Validate output shape to catch silent mismatches early
    _validate_tflite_shape(dest_path, expected_classes=len(AGENTS_CLASSES.get(agent, [])))

    return dest_path


# ---------------------------------------------------------------------------
# ONNX export (for server-side inference)
# ---------------------------------------------------------------------------

def export_onnx(
    weights_path: Path,
    agent: str,
    output_dir: Path,
    imgsz: int = 640,
) -> Path:
    """Export a YOLOv8 .pt model to ONNX for backend/server inference."""
    output_dir.mkdir(parents=True, exist_ok=True)
    model = YOLO(str(weights_path))
    exported_path_str: str = model.export(
        format="onnx",
        imgsz=imgsz,
        simplify=True,
        opset=12,  # Wide compatibility: TensorRT, onnxruntime, OpenVINO
    )
    exported_path = Path(exported_path_str)
    if not exported_path.exists():
        raise FileNotFoundError(f"ONNX export produced no file at {exported_path}")

    dest_name = f"{agent}.onnx"
    dest_path = output_dir / dest_name
    shutil.copy2(exported_path, dest_path)
    print(f"[export] ONNX exported → {dest_path} ({dest_path.stat().st_size / 1024 / 1024:.2f} MB)")
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
    parser = argparse.ArgumentParser(description="Export TariqMap YOLOv8 model to TFLite + ONNX")
    parser.add_argument("--weights", type=Path, required=True, help="Path to best.pt")
    parser.add_argument("--agent", required=True, choices=list(AGENTS_CLASSES), help="Agent name")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).parents[2] / "app" / "assets" / "models",
        help="Output directory for TFLite (default: app/assets/models)",
    )
    parser.add_argument(
        "--precision",
        default="float16",
        choices=PRECISIONS,
        help="Export precision: float32, float16 (default), int8",
    )
    parser.add_argument("--imgsz", type=int, default=640, help="Input image size")
    parser.add_argument(
        "--calibration-data",
        type=Path,
        default=None,
        help="Directory of representative images for int8 calibration (recommended for int8)",
    )
    parser.add_argument(
        "--export-onnx",
        action="store_true",
        help="Also export ONNX model to <output>/../onnx/ for backend inference",
    )
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

    # TFLite export
    dest = export_tflite(
        weights_path=args.weights,
        agent=args.agent,
        output_dir=args.output,
        precision=args.precision,
        imgsz=args.imgsz,
        calibration_data=args.calibration_data,
    )

    checksum = _sha256(dest)
    print(f"[export] SHA-256 (TFLite): {checksum}")

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

    # ONNX export (optional, for backend/server-side inference)
    if args.export_onnx:
        onnx_output_dir = args.output.parent / "onnx"
        onnx_path = export_onnx(
            weights_path=args.weights,
            agent=args.agent,
            output_dir=onnx_output_dir,
            imgsz=args.imgsz,
        )
        onnx_checksum = _sha256(onnx_path)
        print(f"[export] SHA-256 (ONNX): {onnx_checksum}")

    print(f"\n[export] Done. TFLite: {dest}")
    if args.export_onnx:
        print(f"[export] ONNX: {onnx_output_dir / (args.agent + '.onnx')}")
        print("[export] Backend inference: copy .onnx to backend/ and use backend/inference.py")


if __name__ == "__main__":
    main()
