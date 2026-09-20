# TariqMap Backend

A simple FastAPI mock backend designed to ingest sync data from the TariqMap Flutter application.

## Prerequisites

- Python 3.10+
- `pip` or `uv` for dependency management

## Setup

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

2. Run the server:
   ```bash
   uvicorn main:app --host 0.0.0.0 --port 8000 --reload
   ```

## Connectivity

- **Local Simulator/Device on same network**: Connect to `http://<YOUR_LOCAL_IP>:8000/v1`
- **Android Emulator**: The app is configured to use `http://10.0.2.2:8000/v1`
- **iOS Simulator / Web**: The app is configured to use `http://127.0.0.1:8000/v1`

## Endpoints

- `GET /v1/health`: Returns server status and observation count
- `POST /v1/observations`: Upload an Observation (idempotent). GPS-missing payloads (`gpsAvailable: false`, lat/lon 0) are accepted.
- `GET /v1/stats`: Returns analytics based on uploaded observations
- `GET /v1/contract`: Read-only actors (peers) and incident statuses (`DETECTED`…`ARCHIVED`)

Incident CRUD, SIG matching, and RAG are **PLANNED**. This mock is not a production GIS.
