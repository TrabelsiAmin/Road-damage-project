# TariqMap Backend

FastAPI backend for the TariqMap Flutter application. Observation metadata and detection results are persisted in the TariqMap Supabase project; the backend no longer uses an in-memory observation store.

## Prerequisites

- Python 3.10+
- `pip` or `uv`
- A Supabase project with the TariqMap schema

## Setup

1. Install dependencies:

   ```bash
   pip install -r requirements.txt
   ```

2. Create a local environment file:

   ```bash
   cp .env.example .env
   ```

3. Set the Supabase secret in your shell or `.env` file. The backend reads:

   ```bash
   export TARIQMAP_SUPABASE_URL=https://lendqcjihusqkmxansbl.supabase.co
   export TARIQMAP_SUPABASE_SERVICE_ROLE_KEY=your-supabase-secret-key
   ```

   **Never commit `.env` or the service-role/secret key.** The `.gitignore` file excludes environment files while keeping `.env.example` tracked.

4. Start the server from the `backend` directory:

   ```bash
   uvicorn main:app --host 0.0.0.0 --port 8000 --reload
   ```

## Supabase persistence mapping

`POST /v1/observations` writes the mobile payload to the normalized Supabase schema:

- `observations` — capture metadata, organization, priority, and model bundle
- `locations` — latitude, longitude, and GPS accuracy
- `agent_runs` — one row per detector run
- `detections` — normalized class, confidence, and bounding-box values
- `sync_receipts` — idempotency key and payload hash

The current mobile client sends a local `imagePath`, not image bytes. Therefore this backend stores the observation and detection metadata but does not upload the image to the private `observations` Storage bucket yet.

The backend maps the current app actors to the seeded Supabase organizations:

| App actor | Supabase organization |
|---|---|
| `Municipality` | `Municipality` |
| `Ministry of Equipment` | `Ministry of Equipment` |
| `Tunisia Autoroutes` | `Tunisia Autoroutes` |

## Endpoints

- `GET /v1/health` — Supabase connectivity and observation count
- `POST /v1/observations` — persist an observation and its child rows; repeated uploads are idempotent
- `GET /v1/observations` — list recent observations from Supabase
- `GET /v1/observations/{id}` — read one observation with location, agent runs, and detections
- `GET /v1/stats` — aggregate Supabase-backed statistics
- `POST /v1/detect` — optional server-side ONNX inference when models are installed
- `GET /v1/detect/agents` — list available ONNX agents

If Supabase is not configured, database endpoints return `503` instead of silently falling back to memory.
