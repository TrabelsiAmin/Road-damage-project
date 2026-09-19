# Training

## Status

**REQUIRES LABELED DATA** and a GPU for a serious YOLOv8 run.

This environment (and many laptops) has no CUDA. `src.train` exits unless `--allow-cpu` is passed. No mAP, precision, or recall figures are recorded in this repo because **no training run has completed on RDD**.

## Do not

- Train on `Global_Potholes_Dataset-image`
- Invent per-class AP
- Bundle a random `.pt` / `.tflite` so the app "looks" trained

## Do

1. Put RDD2022/RDD2024 on disk (see [dataset.md](dataset.md)).
2. Convert VOC → YOLO: `python -m src.convert_rdd_voc`
3. Audit: `python -m src.analyze_labeled_dataset`
4. Split per agent: `python -m src.prepare_dataset`
5. Baseline (YOLOv8n, 640):

```bash
python -m src.train --agent pavement --data config/pavement.yaml \
  --weights yolov8n.pt --epochs 100 --imgsz 640 --seed 42
```

Hyperparameters default from `config/augmentation.yaml` / `config/baseline.yaml`:

| Item | Baseline default |
| --- | --- |
| Model | YOLOv8n |
| Image size | 640 |
| Epochs | 100 (augmentation.yaml lists 150; CLI overrides) |
| Batch | 16 |
| Optimizer | SGD |
| lr0 | 0.01 |
| Augmentation | mosaic 0.8, fliplr 0.5, hsv, small rotation — see YAML |

6. Fine-tune the **same** agent from `best.pt` with `--finetune` (LR × 0.1) and **the same** test split via `src.evaluate`.
7. Small-object investigation: compare YOLOv8n/640 vs YOLOv8s/640 vs YOLOv8s/960 **only if VRAM allows**. Pick using validation + mobile latency, not parameter count.

The surface agent (D50/D60/D90) should be skipped when `analyze_labeled_dataset` reports those classes absent.

## Export

```bash
python -m src.export --weights runs/pavement_baseline/weights/best.pt --agent pavement --precision float16
python -m src.verify_tflite --model ../app/assets/models/pavement.tflite
```

Copy into `app/assets/models/` only after verify reports `ok_for_flutter: true`. Flutter preprocesses with **letterbox** (pad 114), not stretch-resize.
