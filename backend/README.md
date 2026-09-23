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
   uvicorn main:app --host 0.0.0.0 --port 8080 --reload
   ```

## Connectivity

- **Local Simulator/Device on same network**: Connect to `http://<YOUR_LOCAL_IP>:8080/v1`
- **Android Emulator**: The app is configured to use `http://10.0.2.2:8080/v1`
- **iOS Simulator / Web**: The app is configured to use `http://127.0.0.1:8080/v1`

## Endpoints

- `GET /v1/health`: Returns server status and observation count
- `POST /v1/observations`: Upload an Observation (idempotent)
- `GET /v1/stats`: Returns analytics based on uploaded observations
- `POST /v1/detect`: Runs StreetSense Roboflow inference when configured; otherwise uses local ONNX models.

## StreetSense model configuration

The reference project at [Kanishk1420/StreetSense-Road-Damage-Detection](https://github.com/Kanishk1420/StreetSense-Road-Damage-Detection) uses the hosted Roboflow model `road-damage-detection-apxtk/5`. This project integrates that model through the backend rather than shipping the API key in the Flutter binary.

Set the key before starting the server:

```bash
export STREETSENSE_ROBOFLOW_API_KEY="your-roboflow-key"
# Optional override if the model version changes:
export STREETSENSE_ROBOFLOW_MODEL="road-damage-detection-apxtk/5"
uvicorn main:app --host 0.0.0.0 --port 8080
```

The adapter converts Roboflow pixel-space boxes and natural-language labels into the app's normalized D-code contract (`D00`, `D10`, `D20`, `D40`, `D50`, `D60`, `D90`). Unknown labels are reported instead of silently being merged. The Flutter app calls `/v1/detect` first and falls back to its existing local TFLite/mock runners if the backend is unavailable.
