"""Server-side YOLO inference using ONNX Runtime.

Loads a pre-exported ONNX model (produced by training/src/export.py --export-onnx)
and exposes a /v1/detect endpoint for image-based inference.

This allows the backend to:
- Re-validate detections uploaded by the mobile app
- Process images that couldn't be run on-device (web upload)
- Run richer multi-agent ensemble on server hardware

Model setup:
    1. Train: python -m src.train --agent cracks --data config/cracks.yaml
    2. Export: python -m src.export --weights runs/cracks/weights/best.pt
               --agent cracks --export-onnx
    3. Copy the .onnx file(s) to backend/models/

Usage:
    # Start server with inference enabled
    TARIQMAP_MODELS_DIR=./models uvicorn main:app --reload --port 8080
"""
from __future__ import annotations

import base64
import io
import os
import time
from pathlib import Path
from typing import Any

import numpy as np

try:
    import onnxruntime as ort
    _ONNX_AVAILABLE = True
except ImportError:
    _ONNX_AVAILABLE = False

try:
    from PIL import Image
    _PIL_AVAILABLE = True
except ImportError:
    _PIL_AVAILABLE = False


# ---------------------------------------------------------------------------
# Constants (must match TFLiteAgentRunner and train.py)
# ---------------------------------------------------------------------------

INPUT_SIZE = 640

CLASS_NAMES: dict[int, str] = {
    0: "D00",  # Longitudinal crack
    1: "D10",  # Transverse crack
    2: "D20",  # Alligator cracking
    3: "D40",  # Pothole
    4: "D50",  # Faded pedestrian crossing
    5: "D60",  # Faded lane marking
    6: "D90",  # Rutting
}

# Per-class confidence thresholds — mirrored from augmentation.yaml
CLASS_THRESHOLDS: dict[str, float] = {
    "D00": 0.35,
    "D10": 0.35,
    "D20": 0.28,
    "D40": 0.42,
    "D50": 0.28,
    "D60": 0.28,
    "D90": 0.32,
}

AGENTS: dict[str, list[str]] = {
    "cracks":   ["D00", "D10"],
    "pavement": ["D20", "D40"],
    "surface":  ["D50", "D60", "D90"],
}

DEFAULT_IOU_THRESHOLD = 0.45


# ---------------------------------------------------------------------------
# Model loader
# ---------------------------------------------------------------------------

class InferenceSession:
    """Wraps an onnxruntime InferenceSession with metadata."""

    def __init__(self, agent: str, model_path: Path) -> None:
        if not _ONNX_AVAILABLE:
            raise ImportError(
                "onnxruntime is not installed. "
                "pip install onnxruntime  (CPU)  or  onnxruntime-gpu  (GPU)"
            )
        self.agent      = agent
        self.model_path = model_path
        self.session    = ort.InferenceSession(
            str(model_path),
            providers=["CUDAExecutionProvider", "CPUExecutionProvider"],
        )
        self.input_name = self.session.get_inputs()[0].name
        print(f"[inference] Loaded {agent} model: {model_path}")

    def run(self, image_rgb: "np.ndarray") -> "np.ndarray":
        """Run inference on a [H, W, 3] uint8 RGB image. Returns raw output tensor."""
        if not _PIL_AVAILABLE:
            raise ImportError("pillow is required: pip install pillow")

        # Resize to 640×640, normalise to [0, 1], add batch dim → [1, 3, H, W] float32
        pil_img = Image.fromarray(image_rgb).resize((INPUT_SIZE, INPUT_SIZE))
        arr = np.array(pil_img, dtype=np.float32) / 255.0          # [H, W, 3]
        arr = arr.transpose(2, 0, 1)[np.newaxis, ...]               # [1, 3, H, W]

        outputs = self.session.run(None, {self.input_name: arr})
        return outputs[0]  # [1, 4+num_classes, 8400]


# ---------------------------------------------------------------------------
# IoU helpers (pure Python / numpy — no CV2 dependency)
# ---------------------------------------------------------------------------

def _iou(box_a: list[float], box_b: list[float]) -> float:
    """Compute IoU for boxes in [x1, y1, x2, y2] format."""
    ix1 = max(box_a[0], box_b[0])
    iy1 = max(box_a[1], box_b[1])
    ix2 = min(box_a[2], box_b[2])
    iy2 = min(box_a[3], box_b[3])

    iw = max(0.0, ix2 - ix1)
    ih = max(0.0, iy2 - iy1)
    intersection = iw * ih
    if intersection == 0:
        return 0.0

    area_a = (box_a[2] - box_a[0]) * (box_a[3] - box_a[1])
    area_b = (box_b[2] - box_b[0]) * (box_b[3] - box_b[1])
    union = area_a + area_b - intersection
    return intersection / union if union > 0 else 0.0


def _nms_per_class(detections: list[dict]) -> list[dict]:
    """Class-aware NMS: suppresses duplicates within each class independently."""
    by_class: dict[str, list[dict]] = {}
    for d in detections:
        by_class.setdefault(d["classCode"], []).append(d)

    result: list[dict] = []
    for class_dets in by_class.values():
        sorted_dets = sorted(class_dets, key=lambda d: d["confidence"], reverse=True)
        kept: list[dict] = []
        suppressed = set()
        for i, d in enumerate(sorted_dets):
            if i in suppressed:
                continue
            kept.append(d)
            for j in range(i + 1, len(sorted_dets)):
                if j in suppressed:
                    continue
                b1 = d["box"]
                b2 = sorted_dets[j]["box"]
                box_a = [b1["x"], b1["y"], b1["x"] + b1["width"], b1["y"] + b1["height"]]
                box_b = [b2["x"], b2["y"], b2["x"] + b2["width"], b2["y"] + b2["height"]]
                if _iou(box_a, box_b) > DEFAULT_IOU_THRESHOLD:
                    suppressed.add(j)
        result.extend(kept)

    return sorted(result, key=lambda d: d["confidence"], reverse=True)


# ---------------------------------------------------------------------------
# Decode raw model output → detections
# ---------------------------------------------------------------------------

def decode_detections(
    raw_output: "np.ndarray",
    agent_classes: list[str],
) -> list[dict[str, Any]]:
    """Decode raw [1, 4+C, 8400] YOLO output to a list of detection dicts."""
    output = raw_output[0]        # [4+C, 8400]
    num_anchors = output.shape[1]
    num_classes = len(CLASS_NAMES)

    raw: list[dict] = []
    for anchor in range(num_anchors):
        scores = output[4:, anchor]
        best_class = int(np.argmax(scores))
        best_score = float(scores[best_class])

        class_name = CLASS_NAMES.get(best_class)
        if class_name is None:
            continue
        if class_name not in agent_classes:
            continue
        if best_score < CLASS_THRESHOLDS.get(class_name, 0.35):
            continue

        cx = float(np.clip(output[0, anchor], 0, 1))
        cy = float(np.clip(output[1, anchor], 0, 1))
        bw = float(np.clip(output[2, anchor], 0, 1))
        bh = float(np.clip(output[3, anchor], 0, 1))

        raw.append({
            "classCode":  class_name,
            "confidence": round(best_score, 4),
            "box": {
                "x":      round(max(0.0, cx - bw / 2), 4),
                "y":      round(max(0.0, cy - bh / 2), 4),
                "width":  round(bw, 4),
                "height": round(bh, 4),
            },
        })

    return _nms_per_class(raw)


# ---------------------------------------------------------------------------
# Registry — loaded lazily per request
# ---------------------------------------------------------------------------

_sessions: dict[str, InferenceSession] = {}


def _models_dir() -> Path:
    return Path(os.environ.get("TARIQMAP_MODELS_DIR", Path(__file__).parent / "models"))


def get_session(agent: str) -> InferenceSession | None:
    if agent in _sessions:
        return _sessions[agent]

    model_path = _models_dir() / f"{agent}.onnx"
    if not model_path.exists():
        return None

    try:
        session = InferenceSession(agent, model_path)
        _sessions[agent] = session
        return session
    except Exception as exc:
        print(f"[inference] Failed to load {agent}: {exc}")
        return None


def list_available_agents() -> list[str]:
    """Return names of agents whose .onnx files exist in the models directory."""
    models_dir = _models_dir()
    if not models_dir.exists():
        return []
    return [p.stem for p in models_dir.glob("*.onnx") if p.stem in AGENTS]


# ---------------------------------------------------------------------------
# High-level detect function (called from main.py)
# ---------------------------------------------------------------------------

def detect_image(image_b64: str, agents: list[str] | None = None) -> dict[str, Any]:
    """Run YOLO detection on a base64-encoded image.

    Args:
        image_b64: Base64-encoded JPEG/PNG bytes.
        agents: Which agents to run. Defaults to all available.

    Returns:
        dict with 'agent_results', 'total_detections', 'latency_ms'.
    """
    if not _PIL_AVAILABLE:
        raise RuntimeError("pillow is required: pip install pillow")

    # Decode image
    raw_bytes = base64.b64decode(image_b64)
    pil_image = Image.open(io.BytesIO(raw_bytes)).convert("RGB")
    image_array = np.array(pil_image, dtype=np.uint8)

    target_agents = agents or list_available_agents()
    agent_results = []
    t0 = time.perf_counter()

    for agent_name in target_agents:
        session = get_session(agent_name)
        if session is None:
            agent_results.append({
                "agent":      agent_name,
                "detections": [],
                "error":      f"Model not found: {_models_dir() / agent_name}.onnx",
            })
            continue

        try:
            raw_output  = session.run(image_array)
            agent_classes = AGENTS.get(agent_name, list(CLASS_NAMES.values()))
            detections  = decode_detections(raw_output, agent_classes)
            agent_results.append({
                "agent":      agent_name,
                "detections": detections,
            })
        except Exception as exc:
            agent_results.append({
                "agent":      agent_name,
                "detections": [],
                "error":      str(exc),
            })

    latency_ms = round((time.perf_counter() - t0) * 1000, 1)
    total = sum(len(r.get("detections", [])) for r in agent_results)

    return {
        "agent_results":    agent_results,
        "total_detections": total,
        "latency_ms":       latency_ms,
        "available_agents": list_available_agents(),
    }
