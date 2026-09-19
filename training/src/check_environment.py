"""Record what this machine can actually run. Does not invent mAP."""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def _which(name: str) -> str | None:
    return shutil.which(name)


def _cuda_via_nvidia_smi() -> dict:
    bin_path = _which("nvidia-smi")
    if not bin_path:
        return {"available": False, "reason": "nvidia-smi not found"}
    try:
        proc = subprocess.run(
            [bin_path, "--query-gpu=name,memory.total", "--format=csv,noheader"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        if proc.returncode != 0:
            return {"available": False, "reason": proc.stderr.strip() or "nvidia-smi failed"}
        gpus = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        return {"available": bool(gpus), "gpus": gpus, "nvidia_smi": bin_path}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"available": False, "reason": str(exc)}


def _torch_cuda() -> dict:
    try:
        import torch  # type: ignore
    except ImportError:
        return {"installed": False, "cuda": False}
    return {
        "installed": True,
        "version": getattr(torch, "__version__", None),
        "cuda": bool(torch.cuda.is_available()),
    }


def _ultralytics() -> dict:
    try:
        import ultralytics  # type: ignore
    except ImportError:
        return {"installed": False}
    return {"installed": True, "version": getattr(ultralytics, "__version__", None)}


def inspect(training_root: Path, labeled_hint: Path) -> dict:
    xml = list(labeled_hint.rglob("*.xml")) if labeled_hint.exists() else []
    report = {
        "status": "OK",
        "inspected_at_utc": datetime.now(timezone.utc).isoformat(),
        "ffmpeg": _which("ffmpeg"),
        "ffprobe": _which("ffprobe"),
        "cuda": _cuda_via_nvidia_smi(),
        "torch": _torch_cuda(),
        "ultralytics": _ultralytics(),
        "labeled_extract": {
            "path": str(labeled_hint),
            "exists": labeled_hint.exists(),
            "xml_count": len(xml),
            "usable": len(xml) > 0,
        },
        "can_train_yolov8": False,
        "can_mux_video": _which("ffmpeg") is not None and _which("ffprobe") is not None,
        "notes": [],
    }
    cuda_ok = bool(report["cuda"].get("available")) or bool(report["torch"].get("cuda"))
    labeled = report["labeled_extract"]["usable"]
    ultra = bool(report["ultralytics"].get("installed"))
    report["can_train_yolov8"] = bool(cuda_ok and labeled and ultra)
    if not cuda_ok:
        report["notes"].append("No NVIDIA GPU. src.train will refuse unless --allow-cpu.")
    if not labeled:
        report["notes"].append("No local RDD VOC XML. Do not train on Global Potholes.")
    if not ultra:
        report["notes"].append("ultralytics is not installed in this environment.")
    if report["can_mux_video"]:
        report["notes"].append("FFmpeg CLI present — annotated MP4 muxer can run here.")
    return report


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--labeled",
        type=Path,
        default=root / "data" / "raw" / "rdd2022",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=root / "reports" / "environment.json",
    )
    args = parser.parse_args()
    report = inspect(root, args.labeled)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
