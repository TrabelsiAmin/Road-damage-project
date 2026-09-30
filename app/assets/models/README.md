# Model assets

STATUS: **REQUIRES MODEL**

This directory holds `model-bundles.json` only. Validated YOLOv8 → TFLite
files (`cracks.tflite`, `pavement.tflite`, `surface.tflite`) are **not**
committed.

After a real training + `python -m src.export` + `python -m src.verify_tflite`
run, place the checksummed `.tflite` files here or publish them as GitHub
Release assets and update the SHA-256 fields.

Do not add a randomly initialized or dummy TFLite graph.
