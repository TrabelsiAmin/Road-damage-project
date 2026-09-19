"""Post-export checks for TFLite files destined for the Flutter app.

Does not install weights into app/assets until this script reports OK.
A missing file yields status MODEL_PENDING — never a fake model.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

EXPECTED_INPUT_NHWC = [1, 640, 640, 3]
EXPECTED_CLASS_COUNT = 7


def inspect_tflite(path: Path) -> dict[str, Any]:
    report: dict[str, Any] = {
        "status": "MODEL_PENDING",
        "path": str(path),
        "size_bytes": None,
        "input_shape": None,
        "output_shape": None,
        "ok_for_flutter": False,
        "notes": [],
    }
    if not path.exists():
        report["notes"].append(
            "No TFLite file. Train + export a real YOLOv8 model before bundling. "
            "Do not commit a placeholder .tflite."
        )
        return report

    report["size_bytes"] = path.stat().st_size
    try:
        import tensorflow as tf  # type: ignore
    except ImportError:
        try:
            from ai_edge_litert import interpreter as tflite  # type: ignore
            Interpreter = tflite.Interpreter
        except ImportError:
            report["status"] = "FILE_PRESENT_UNVERIFIED"
            report["notes"].append(
                "File exists but neither tensorflow nor ai_edge_litert is installed, "
                "so tensor shapes were not read. Flutter still must not ship this "
                "file until shapes are verified."
            )
            return report
        else:
            interpreter = Interpreter(model_path=str(path))
            interpreter.allocate_tensors()
            inp = interpreter.get_input_details()[0]
            out = interpreter.get_output_details()[0]
            report["input_shape"] = list(inp["shape"])
            report["output_shape"] = list(out["shape"])
            report["input_dtype"] = str(inp.get("dtype"))
            report["output_dtype"] = str(out.get("dtype"))
    else:
        interpreter = tf.lite.Interpreter(model_path=str(path))
        interpreter.allocate_tensors()
        inp = interpreter.get_input_details()[0]
        out = interpreter.get_output_details()[0]
        report["input_shape"] = [int(x) for x in inp["shape"]]
        report["output_shape"] = [int(x) for x in out["shape"]]
        report["input_dtype"] = str(inp.get("dtype"))
        report["output_dtype"] = str(out.get("dtype"))

    shape = report["input_shape"]
    if shape == EXPECTED_INPUT_NHWC:
        report["notes"].append("Input is NHWC 1x640x640x3 as the Flutter runner expects.")
    elif shape and len(shape) == 4 and shape[1] == 3:
        report["notes"].append(
            "Input looks NCHW. Flutter runner currently feeds NHWC — do not install."
        )
    out_shape = report["output_shape"] or []
    if out_shape:
        channels = min(out_shape[1:]) if len(out_shape) >= 2 else None
        report["notes"].append(
            f"Output shape {out_shape}. Flutter decoder accepts [1, 4+C, N] or [1, N, 4+C] "
            f"with C={EXPECTED_CLASS_COUNT}."
        )
        if channels not in {4 + EXPECTED_CLASS_COUNT, None} and (
            len(out_shape) >= 3 and 4 + EXPECTED_CLASS_COUNT not in out_shape
        ):
            report["notes"].append(
                "WARNING: 4+7 channels not found on the output tensor. "
                "Class mapping will be wrong."
            )

    report["ok_for_flutter"] = shape == EXPECTED_INPUT_NHWC
    report["status"] = "OK" if report["ok_for_flutter"] else "VERIFY_FAILED"
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("reports/tflite_verify.json"))
    args = parser.parse_args()
    report = inspect_tflite(args.model)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    if report["status"] in {"MODEL_PENDING", "VERIFY_FAILED"}:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
