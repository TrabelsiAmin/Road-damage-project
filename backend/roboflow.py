"""StreetSense Roboflow inference adapter.

The StreetSense reference app uses the Roboflow-hosted model
``road-damage-detection-apxtk/5``.  This adapter keeps the API key on the
backend and converts Roboflow's pixel-space predictions into TariqMap's
normalized D-code detection contract.
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

MODEL_ENDPOINT = os.getenv(
    "STREETSENSE_ROBOFLOW_MODEL",
    "road-damage-detection-apxtk/5",
)
API_KEY = os.getenv("STREETSENSE_ROBOFLOW_API_KEY") or os.getenv("ROBOFLOW_API_KEY")

# The reference model uses natural-language RDD labels. Keep this mapping
# explicit so unknown classes are not silently misclassified.
CLASS_MAP: dict[str, tuple[str, str]] = {
    "longitudinal crack": ("D00", "cracks"),
    "longitudinal_crack": ("D00", "cracks"),
    "transverse crack": ("D10", "cracks"),
    "transverse_crack": ("D10", "cracks"),
    "alligator crack": ("D20", "pavement"),
    "alligator_crack": ("D20", "pavement"),
    "aligator crack": ("D20", "pavement"),
    "alligator": ("D20", "pavement"),
    "pothole": ("D40", "pavement"),
    "potholes": ("D40", "pavement"),
    "faded pedestrian crossing marking": ("D50", "surface"),
    "faded_crossing": ("D50", "surface"),
    "faded lane marking": ("D60", "surface"),
    "faded_lane": ("D60", "surface"),
    "rutting": ("D90", "surface"),
    "rut": ("D90", "surface"),
}


def roboflow_configured() -> bool:
    """Return whether server-side StreetSense inference can be attempted."""
    return bool(API_KEY)


def _class_mapping(label: str) -> tuple[str, str] | None:
    normalized = " ".join(label.strip().lower().replace("-", "_").split())
    return CLASS_MAP.get(normalized) or CLASS_MAP.get(normalized.replace("_", " "))


def _request(image_bytes: bytes, *, confidence: float = 0.35) -> dict[str, Any]:
    if not API_KEY:
        raise RuntimeError(
            "StreetSense inference is not configured. Set STREETSENSE_ROBOFLOW_API_KEY."
        )
    query = urllib.parse.urlencode(
        {"api_key": API_KEY, "confidence": str(int(confidence * 100)), "overlap": "20"}
    )
    url = f"https://detect.roboflow.com/{MODEL_ENDPOINT}?{query}"
    request = urllib.request.Request(
        url,
        data=image_bytes,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Roboflow HTTP {exc.code}: {detail[:400]}") from exc


def detect_roboflow(image_bytes: bytes, *, confidence: float = 0.35) -> dict[str, Any]:
    """Run StreetSense and return the project's /v1/detect response shape."""
    started = time.perf_counter()
    payload = _request(image_bytes, confidence=confidence)
    image = payload.get("image") or {}
    image_width = float(image.get("width") or 1)
    image_height = float(image.get("height") or 1)
    grouped: dict[str, list[dict[str, Any]]] = {
        "cracks": [],
        "pavement": [],
        "surface": [],
    }
    ignored: list[str] = []

    for prediction in payload.get("predictions", []):
        mapped = _class_mapping(str(prediction.get("class", "")))
        if mapped is None:
            ignored.append(str(prediction.get("class", "unknown")))
            continue
        class_code, agent = mapped
        width = max(0.0, float(prediction.get("width", 0)))
        height = max(0.0, float(prediction.get("height", 0)))
        center_x = float(prediction.get("x", 0))
        center_y = float(prediction.get("y", 0))
        box = {
            "x": max(0.0, min(1.0, (center_x - width / 2) / image_width)),
            "y": max(0.0, min(1.0, (center_y - height / 2) / image_height)),
            "width": max(0.0, min(1.0, width / image_width)),
            "height": max(0.0, min(1.0, height / image_height)),
        }
        grouped[agent].append(
            {
                "agent": agent,
                "classCode": class_code,
                "confidence": max(0.0, min(1.0, float(prediction.get("confidence", 0)))),
                "box": box,
            }
        )

    latency_ms = round((time.perf_counter() - started) * 1000)
    results = [
        {
            "agent": agent,
            "detections": detections,
            "error": None,
            "isMock": False,
            "latencyMs": latency_ms,
        }
        for agent, detections in grouped.items()
    ]
    if ignored:
        results.append(
            {
                "agent": "streetsense",
                "detections": [],
                "error": f"Ignored unmapped StreetSense classes: {sorted(set(ignored))}",
                "isMock": False,
                "latencyMs": latency_ms,
            }
        )
    return {
        "agent_results": results,
        "total_detections": sum(len(r["detections"]) for r in results),
        "latency_ms": latency_ms,
        "provider": "streetsense-roboflow",
    }


def list_roboflow_agents() -> list[str]:
    return ["cracks", "pavement", "surface"] if roboflow_configured() else []


__all__ = ["detect_roboflow", "list_roboflow_agents", "roboflow_configured"]
