# Evaluation

## Status

**NOT RUN** for detector metrics on this branch. There is no `best.pt`, so there are no Precision / Recall / mAP numbers.

`src.evaluate` wrote `training/reports/pavement_baseline_test.json` with `status: NOT_RUN` and `metrics: null`. Fine-tune comparison (`src.compare_runs`) is also **NOT RUN**. TFLite verify is `MODEL_PENDING`.

Dataset-side risk (not mAP) from parsing every VOC box:

- D40 (potholes): **20.22%** of boxes are <32×32 px — highest small-object rate among mapped classes
- D00/D10 cracks: ~5% small boxes; D00 is **42.75%** of mapped boxes (imbalance)
- D60: only **793** boxes (1.3%)
- D90: **0** boxes

These are reasons a future baseline may be weak on small potholes and rare lane markings. They are **not** trained-model scores.

## Protocol (when a labeled test split exists)

Same protocol for baseline and fine-tune:

```bash
python -m src.evaluate --weights runs/pavement_baseline/weights/best.pt \
  --data config/pavement.yaml --split test --imgsz 640 \
  --output reports/pavement_baseline_test.json

python -m src.evaluate --weights runs/pavement_ft/weights/best.pt \
  --data config/pavement.yaml --split test --imgsz 640 \
  --output reports/pavement_ft_test.json

python -m src.compare_runs --baseline reports/pavement_baseline_test.json \
  --finetuned reports/pavement_ft_test.json --output reports/compare.json
```

Record:

- model, imgsz, epochs, batch, optimizer, lr, augmentation, training time
- Precision, Recall, mAP50, mAP50-95
- per-class AP
- confusion matrix and PR curves (Ultralytics `plots=True`)
- sample predictions, false positives, false negatives
- small-object subset (D00, D10, D20, D40) — global mAP must not hide them

Selection rule: prefer the model that improves **small-damage** detection enough to justify any extra latency/size on device. Do not auto-select YOLOv8s-960.

## Mobile inference

Until a TFLite file exists, on-device latency is **not measured** (the live camera overlay shows 0 ms or conversion time only, with a REQUIRES MODEL banner). This Linux VM has **no phone/camera device**, so live camera inference was **NOT RUN** here. After install, the camera HUD prints the interpreter `latencyMs`.
