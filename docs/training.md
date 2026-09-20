# Training

## Status

**REQUIRES LABELED DATA** and a GPU for a serious YOLOv8 run.

`python -m src.check_environment` on this branch recorded (`training/reports/environment.json`):

- nvidia-smi: **not found** (on the last probe of this clone)
- torch / ultralytics: **not installed** (on that probe)
- local RDD XML: **0**
- `can_train_yolov8`: **false**
- FFmpeg: **present** (video muxer only)

A sibling agent may be running a real RDD2022 WP3 train on this branch. This file does not invent mAP. `src.train` exits unless `--allow-cpu` is passed. No precision or recall figures are recorded unless `src.evaluate` writes `status: OK`.

## Work-package split (keep three agents)

| Agent | WP | Classes | Priority |
| --- | --- | --- | --- |
| pavement | WP3 Agent Chaussée | D20, D40 | **First baseline / first TFLite** |
| cracks | WP2 Agent Fissures | D00, D10 | After WP3 |
| surface | WP4 Marquage & Surface | D50, D60, D90 | Only if RDD D44/D43 exist; D90 is absent |

`rdd_unified.yaml` is for conversion/audit. `prepare_dataset.py` splits to the three YAMLs above. Do not deploy a mixed 7-class detector.

WP3 is visual 2D only. **No depth estimation** (including D90 rut depth).

## Validated ML path

```
baseline (YOLOv8n, WP3 pavement, imgsz 640)
  → teacher (YOLOv8s / 960 only if VRAM allows)
  → knowledge distillation   python -m src.distill --agent pavement --plan-only
  → student (YOLOv8n)
  → quantization (float16, then int8)
  → src.export + src.verify_tflite
  → three Flutter runners
```

`src.distill` is a **stub**. It writes `reports/distill_plan.json` with `metrics: null`. It will not start a second full YOLO train. Introduce the KD loop later when a teacher `best.pt` exists.

## Do not

- Train on `Global_Potholes_Dataset-image`
- Invent per-class AP
- Bundle a random `.pt` / `.tflite` so the app "looks" trained
- Collapse WP2/WP3/WP4 for convenience

## Do

1. Put RDD2022/RDD2024 on disk (see [dataset.md](dataset.md)).
2. Convert VOC → YOLO: `python -m src.convert_rdd_voc`
3. Audit: `python -m src.analyze_labeled_dataset`
4. Split per agent: `python -m src.prepare_dataset`
5. Baseline **WP3 first** (YOLOv8n, 640):

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
7. Small-object investigation (WP3 D20/D40 first): compare YOLOv8n/640 vs YOLOv8s/640 vs YOLOv8s/960 **only if VRAM allows**. Pick using validation + mobile latency, not parameter count.
8. When a teacher exists: `python -m src.distill --agent pavement` (currently stub / `NOT_RUN`).

The surface agent (D50/D60/D90) should be skipped when `analyze_labeled_dataset` reports those classes absent.

## Export

```bash
python -m src.export --weights runs/pavement_baseline/weights/best.pt --agent pavement --precision float16
python -m src.verify_tflite --model ../app/assets/models/pavement.tflite
```

Copy into `app/assets/models/` only after verify reports `ok_for_flutter: true`. Flutter preprocesses with **letterbox** (pad 114), not stretch-resize.
