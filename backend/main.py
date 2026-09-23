"""TariqMap backend server.

Implements the observation upload contract for local development and hackathon demo.
This is NOT a production server — no authentication, no real storage, no GIS.

Usage:
    pip install fastapi uvicorn
    cd backend && uvicorn main:app --reload --port 8080

Endpoints:
    POST /v1/observations          — Accept uploaded observation (idempotent by id)
    GET  /v1/observations          — List all received observations
    GET  /v1/observations/{id}     — Get one observation by id
    GET  /v1/health                — Health check
    GET  /v1/stats                 — Aggregate stats (count, priority distribution)
    POST /v1/detect                — Server-side YOLO inference (requires ONNX models in backend/models/)

Mobile app integration:
    Set the sync endpoint in api_client.dart to http://<dev-machine-ip>:8080/v1/observations

Server-side YOLO inference:
    1. Export ONNX: python -m src.export --weights runs/cracks/weights/best.pt --agent cracks --export-onnx
    2. Copy backend/models/*.onnx from the training/ output
    3. Set TARIQMAP_MODELS_DIR env var if models are not in backend/models/
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from schemas import ObservationUpload, HealthResponse, StatsResponse
from roboflow import detect_roboflow, list_roboflow_agents, roboflow_configured

# Server-side inference — optional (degrades gracefully if onnxruntime not installed)
try:
    from inference import detect_image, list_available_agents
    _INFERENCE_AVAILABLE = True
except ImportError:
    _INFERENCE_AVAILABLE = False
    def list_available_agents() -> list[str]:  # type: ignore[misc]
        return []

app = FastAPI(
    title="TariqMap API",
    description="Fake backend for hackathon demo. No authentication.",
    version="0.1.0-demo",
)

# Allow all origins for local dev
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("tariqmap")

# In-memory store (not persisted between restarts)
_observations: dict[str, dict[str, Any]] = {}


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/v1/health", response_model=HealthResponse, tags=["infrastructure"])
def health() -> HealthResponse:
    return HealthResponse(
        status="ok",
        server_time=datetime.now(timezone.utc).isoformat(),
        observation_count=len(_observations),
    )


@app.post(
    "/v1/observations",
    status_code=status.HTTP_201_CREATED,
    tags=["observations"],
)
async def create_observation(
    body: ObservationUpload,
    request: Request,
) -> dict:
    obs_id = body.id

    # Idempotency: if already received with same id, return 200 instead of 201
    if obs_id in _observations:
        logger.info("Idempotent repeat upload: %s", obs_id)
        return {"status": "already_received", "id": obs_id}

    stored = body.model_dump()
    stored["received_at"] = datetime.now(timezone.utc).isoformat()
    stored["client_ip"]   = request.client.host if request.client else "unknown"
    _observations[obs_id] = stored

    logger.info(
        "New observation: id=%s actor=%s detections=%d lat=%s lon=%s",
        obs_id,
        body.actor,
        sum(len(r.detections) for r in body.agent_results),
        body.latitude,
        body.longitude,
    )

    return {"status": "created", "id": obs_id}


@app.get(
    "/v1/observations",
    tags=["observations"],
    response_model=list[dict],
)
def list_observations(
    actor: str | None = None,
    sync_status: str | None = None,
    limit: int = 100,
) -> list[dict]:
    results = list(_observations.values())
    if actor:
        results = [r for r in results if r.get("actor") == actor]
    return results[:limit]


@app.get("/v1/observations/{obs_id}", tags=["observations"])
def get_observation(obs_id: str) -> dict:
    obs = _observations.get(obs_id)
    if obs is None:
        raise HTTPException(status_code=404, detail=f"Observation not found: {obs_id}")
    return obs


# ---------------------------------------------------------------------------
# Server-side YOLO detection
# ---------------------------------------------------------------------------

class DetectRequest(BaseModel):
    """Request body for POST /v1/detect."""
    image_b64: str
    """Base64-encoded JPEG or PNG image bytes."""
    agents: list[str] | None = None
    """Subset of agents to run ('cracks', 'pavement', 'surface').
    Defaults to all agents with available ONNX models."""


@app.post("/v1/detect", tags=["inference"])
async def detect(body: DetectRequest) -> dict:
    """Run server-side YOLO inference on an uploaded image.

    Returns agent_results with per-class detections, total_detections count,
    and latency_ms.  Requires ONNX models in backend/models/ — see module
    docstring for setup instructions.

    Responds with 503 if no ONNX models are available (onnxruntime not installed
    or models not copied to backend/models/).
    """
    # StreetSense is the primary detector when its Roboflow key is configured.
    # The existing ONNX implementation remains available as a local fallback.
    if roboflow_configured():
        try:
            import base64

            image_bytes = base64.b64decode(body.image_b64, validate=True)
            result = detect_roboflow(image_bytes)
            logger.info(
                "StreetSense detect: total=%d latency=%.1fms",
                result["total_detections"],
                result["latency_ms"],
            )
            return result
        except Exception as exc:
            logger.exception("StreetSense inference error: %s", exc)
            raise HTTPException(status_code=502, detail=f"StreetSense inference error: {exc}") from exc

    if not _INFERENCE_AVAILABLE:
        raise HTTPException(
            status_code=503,
            detail="Server-side inference unavailable: install onnxruntime + pillow and export ONNX models.",
        )

    available = list_available_agents()
    if not available:
        raise HTTPException(
            status_code=503,
            detail=(
                "No ONNX models found in backend/models/. "
                "Export with: python -m src.export --weights <best.pt> --agent <agent> --export-onnx"
            ),
        )

    try:
        result = detect_image(body.image_b64, agents=body.agents)
    except Exception as exc:
        logger.exception("Inference error: %s", exc)
        raise HTTPException(status_code=500, detail=f"Inference error: {exc}") from exc

    logger.info(
        "Detect: total=%d latency=%.1fms agents=%s",
        result["total_detections"],
        result["latency_ms"],
        [r["agent"] for r in result["agent_results"]],
    )
    return result


@app.get("/v1/detect/agents", tags=["inference"])
def list_detect_agents() -> dict:
    """List which agents have ONNX models available for server-side inference."""
    available = list_roboflow_agents() or list_available_agents()
    return {"available": available, "inference_enabled": bool(available)}


@app.get("/v1/stats", response_model=StatsResponse, tags=["statistics"])
def stats() -> StatsResponse:
    all_obs = list(_observations.values())
    if not all_obs:
        return StatsResponse(total=0, by_actor={}, by_priority={}, by_class={})

    by_actor: dict[str, int] = {}
    by_priority: dict[str, int] = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0}
    by_class: dict[str, int] = {}

    for obs in all_obs:
        actor = obs.get("actor", "Unknown")
        by_actor[actor] = by_actor.get(actor, 0) + 1

        score = obs.get("priority_score", 0)
        if score >= 70:
            by_priority["CRITICAL"] += 1
        elif score >= 40:
            by_priority["HIGH"] += 1
        elif score >= 20:
            by_priority["MEDIUM"] += 1
        else:
            by_priority["LOW"] += 1

        for result in obs.get("agent_results", []):
            for det in result.get("detections", []):
                code = det.get("classCode", "UNKNOWN")
                by_class[code] = by_class.get(code, 0) + 1

    return StatsResponse(
        total=len(all_obs),
        by_actor=by_actor,
        by_priority=by_priority,
        by_class=by_class,
    )


# ---------------------------------------------------------------------------
# Dev entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=True)
