# TariqMap — Road Damage Inspection

Offline-first Flutter app for road-defect detection (images, sampled video frames, live camera) plus a training pipeline for YOLOv8 → TFLite.

This repository is a working product slice, not a trained production model.

## Status at a glance

| Area | Status |
| --- | --- |
| Still-image capture + observation log + mock/demo banners | **CURRENTLY WORKING** (demo/mock until a real model is installed) |
| Video: MP4/MOV → JPEG frame extract → inference → annotated frames + contact sheet | **CURRENTLY WORKING** (pipeline). **REQUIRES MODEL** for real boxes. Encoded output MP4 is **CURRENTLY WORKING** when FFmpeg is on PATH (verified H.264 decode); **NOT AVAILABLE** on stock Android/iOS — see [docs/video-detection.md](docs/video-detection.md) |
| Live camera YUV/BGRA conversion, preview-aligned boxes, temporal smoothing, latency | **CURRENTLY WORKING** (pipeline). **REQUIRES MODEL** for real boxes |
| TFLite runner (letterbox + inverse mapping + YOLO decode) | **CURRENTLY WORKING** (code). **REQUIRES MODEL** (no `.tflite` is bundled) |
| FastAPI observation ingest | **DEMO/MOCK** (in-memory, no auth) |
| Global Potholes 29,120 JPEGs | **DEMO/REFERENCE only**. Unlabeled. **Not used for training.** Removed from git tracking |
| YOLOv8 baseline / fine-tune / mAP | **REQUIRES LABELED DATA** + GPU. Metrics are **not claimed** |
| D50 / D60 (faded markings) | Trainable **only if** RDD D44 / D43 exist in the dump you download |
| D90 (rutting) | **ABSENT** from RDD2022/RDD2024 — taxonomy only |

## Data strategy (Option A)

Do **not** train YOLO on `Global_Potholes_Dataset-image`. That dump has images and no labels.

Train on a labeled road-damage set such as **RDD2022 / RDD2024** after converting Pascal VOC XML → YOLO with the mapping in `training/config/source-class-map.json`.

```
D00 → D00   longitudinal crack
D10 → D10   transverse crack
D20 → D20   alligator crack
D40 → D40   pothole
D43 → D60   white-line blur → faded lane marking   (only if present)
D44 → D50   crosswalk blur → faded crossing        (only if present)
D90         not in RDD — do not invent a mapping
```

Pipeline:

```bash
cd training
python -m src.check_environment
python -m src.download_rdd --fetch-metadata --dest data/raw/rdd2022
python -m src.convert_rdd_voc --source data/raw/rdd2022 --output data/raw/rdd_yolo
python -m src.analyze_labeled_dataset --dataset data/raw/rdd_yolo --output reports/rdd_analysis.json
python -m src.prepare_dataset --source data/raw/rdd_yolo --output data/processed --class-map config/source-class-map.json
python -m src.train --agent pavement --data config/pavement.yaml --weights yolov8n.pt
python -m src.evaluate --weights runs/pavement_baseline/weights/best.pt --data config/pavement.yaml --split test
python -m src.export --weights runs/pavement_baseline/weights/best.pt --agent pavement
python -m src.verify_tflite --model ../app/assets/models/pavement.tflite
```

`download_rdd --fetch-metadata` records Figshare access; it does not pull the 13.3 GB zip. If this machine has no CUDA, `src.train` refuses to start unless you pass `--allow-cpu`. It will not fabricate mAP.

Desktop video mux (FFmpeg):

```bash
python -m src.process_video --input clip.mp4 --output /tmp/annotated.mp4 --fps 2
```

## Run the app

```bash
cd app
flutter pub get
flutter run
```

Without TFLite weights the UI shows **DEMO MOCK INFERENCE** on gallery import. Video and live camera **do not** stamp mock boxes onto frames.

## Run the mock backend

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8765
```

## Tests

```bash
cd app && flutter test
cd training && python -m unittest discover -s tests
```

## Docs

- [docs/dataset.md](docs/dataset.md) — labeled vs unlabeled, class taxonomy
- [docs/dataset-audit.md](docs/dataset-audit.md) — Global Potholes audit (corrected)
- [docs/video-detection.md](docs/video-detection.md)
- [docs/training.md](docs/training.md)
- [docs/evaluation.md](docs/evaluation.md)
- [app/README.md](app/README.md)

## Models

Do not commit `.pt` / `.tflite` checkpoints. After a validated export, use GitHub Releases (or Git LFS) and put checksums in `app/assets/models/model-bundles.json`.
