"""TariqMap backend server.

Implements the observation upload contract and persists normalized records in
the TariqMap Supabase project. Supabase Auth is not yet wired into the mobile
client, so this backend uses its server-side secret for ingestion.

Usage:
    pip install fastapi uvicorn
    cd backend && uvicorn main:app --reload --port 8000

Endpoints:
    POST /v1/observations          — Accept uploaded observation (idempotent by id)
    GET  /v1/observations          — List all received observations
    GET  /v1/observations/{id}     — Get one observation by id
    GET  /v1/health                — Health check
    GET  /v1/stats                 — Aggregate stats (count, priority distribution)
    POST /v1/detect                — Server-side YOLO inference (requires ONNX models in backend/models/)

Mobile app integration:
    Set the sync endpoint in api_client.dart to http://<dev-machine-ip>:8000/v1/observations

Server-side YOLO inference:
    1. Export ONNX: python -m src.export --weights runs/cracks/weights/best.pt --agent cracks --export-onnx
    2. Copy backend/models/*.onnx from the training/ output
    3. Set TARIQMAP_MODELS_DIR env var if models are not in backend/models/
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Query, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from schemas import ObservationUpload, HealthResponse, StatsResponse
from supabase_store import SupabaseNotConfigured, SupabaseStore, redact_secrets

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

store = SupabaseStore()


def _scrub_validation_error(error: dict) -> dict:
    """Keep the standard detail fields, but do not echo images or tokens."""
    item = dict(error)
    loc = item.get("loc") or ()
    raw = item.get("input")
    sensitive = "image_b64" in loc
    if isinstance(raw, str) and (sensitive or len(raw) > 256 or redact_secrets(raw) != raw):
        item["input"] = "[redacted]"
    return item


@app.exception_handler(RequestValidationError)
async def hide_sensitive_validation_input(
    request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    del request
    details = [_scrub_validation_error(err) for err in jsonable_encoder(exc.errors())]
    return JSONResponse(status_code=422, content={"detail": details})


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/v1/health", response_model=HealthResponse, tags=["infrastructure"])
def health() -> HealthResponse:
    if not store.configured:
        raise HTTPException(status_code=503, detail="Supabase is not configured")
    return HealthResponse(
        status="ok",
        server_time=datetime.now(timezone.utc).isoformat(),
        observation_count=store.health_count(),
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
    try:
        result = store.insert_observation(body, request.headers.get("Idempotency-Key", body.id))
    except SupabaseNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except RuntimeError as exc:
        logger.warning("Supabase observation write failed")
        raise HTTPException(
            status_code=502,
            detail="The observation store rejected the request",
        ) from exc
    logger.info("Supabase observation sync: id=%s status=%s", body.id, result["status"])
    return result


@app.get(
    "/v1/observations",
    tags=["observations"],
    response_model=list[dict],
)
def list_observations(
    actor: str | None = None,
    sync_status: str | None = None,
    limit: int = Query(default=100, ge=1, le=500),
) -> list[dict]:
    try:
        return store.list_observations(actor, limit)
    except SupabaseNotConfigured as exc:
        raise HTTPException(status_code=503, detail="Supabase is not configured") from exc
    except RuntimeError as exc:
        logger.warning("Supabase observation list failed")
        raise HTTPException(
            status_code=502,
            detail="The observation store rejected the request",
        ) from exc


@app.get("/v1/observations/{obs_id}", tags=["observations"])
def get_observation(obs_id: str) -> dict:
    try:
        obs = store.get_observation(obs_id)
    except SupabaseNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except RuntimeError as exc:
        logger.warning("Supabase observation read failed")
        raise HTTPException(
            status_code=502,
            detail="The observation store rejected the request",
        ) from exc
    if obs is None:
        raise HTTPException(status_code=404, detail=f"Observation not found: {obs_id}")
    return obs


# ---------------------------------------------------------------------------
# Server-side YOLO detection
# ---------------------------------------------------------------------------

class DetectRequest(BaseModel):
    """Request body for POST /v1/detect."""
    image_b64: str = Field(min_length=16, max_length=12_000_000)
    """Base64-encoded JPEG or PNG image bytes. Not logged."""
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
        logger.warning("Inference failed")
        raise HTTPException(status_code=500, detail="Inference failed") from exc

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
    return {
        "available": list_available_agents(),
        "inference_enabled": _INFERENCE_AVAILABLE,
    }


@app.get("/v1/stats", response_model=StatsResponse, tags=["statistics"])
def stats() -> StatsResponse:
    try:
        return StatsResponse(**store.stats())
    except SupabaseNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except RuntimeError as exc:
        logger.warning("Supabase stats read failed")
        raise HTTPException(
            status_code=502,
            detail="The observation store rejected the request",
        ) from exc


# ---------------------------------------------------------------------------
# Dev entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=True)
