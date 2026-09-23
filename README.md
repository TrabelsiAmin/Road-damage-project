# TariqMap 🛣️

**Offline-First Road Damage Inspection**

TariqMap is a production-grade, offline-first mobile application (Android/iOS) designed for real-time road anomaly detection using on-device Machine Learning. It empowers field inspectors and crowd-sourced contributors to capture road defects via images, live video streams, or video file imports, automatically logging GPS coordinates and severity scores.

## Key Features

- **Offline-First Inference**: Runs the trained `oracl4/RoadDamageDetection` YOLOv8 Small model as a bundled float32 TFLite model directly on the device. No internet connection or detection API is required.
- **Multi-Modal Input**: Supports importing static images, importing pre-recorded video sequences, and a live-camera inspection mode with real-time bounding box overlays and FPS diagnostics.
- **Robust Sync Engine**: An idempotent, retryable background synchronization coordinator pushes observations to the central backend whenever connectivity is restored.
- **Prioritization Engine**: Automatically calculates an severity/priority score (0-100) based on defect class (e.g., severe potholes vs. minor longitudinal cracks) and inference confidence.
- **RDD2022 Classes**: Detects longitudinal cracks, transverse cracks, alligator cracks, and potholes, with normalized bounding boxes and class-aware NMS.
- **Mock/Demo Transparency**: Built for honesty. The UI clearly flags "Mock" inference only on unsupported platforms (e.g., Flutter Web) or if the bundled model cannot load.

## Architecture

The project is structured into three main layers:
1. **Training Pipeline (`/training`)**: Scripts for auditing datasets (Global Potholes Dataset), augmenting data, training YOLOv8n, and exporting to TFLite and PyTorch Mobile formats.
2. **Mobile Application (`/app`)**: The Flutter mobile application responsible for UI, SQLite persistence, camera handling, and TFLite execution.
3. **Backend (`/backend`)**: A lightweight FastAPI mock ingestion server representing the remote data lake.

## Getting Started

### 1. Mobile App
```bash
cd app
flutter pub get
flutter run
```

### 2. Backend Server
```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## Hackathon Demonstration Guide

For a full breakdown of how to demo TariqMap, please see [docs/hackathon-demo.md](docs/hackathon-demo.md). It details how to showcase the offline capability, the sync recovery, and the live camera mode.

## Dataset & Training Audit

Honesty in AI is paramount. Please see [docs/dataset-audit.md](docs/dataset-audit.md) for a comprehensive review of the `Global_Potholes_Dataset-image`. It details known label drifts, missing masks, and our methodology for training an ethical, transparent model.
