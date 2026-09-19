# Evaluation

## Status

**NOT RUN** on this branch. There is no `best.pt`, so there are no numbers.

`src.evaluate` writes `status: NOT_RUN` when weights are missing instead of filling mAP with placeholders.

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

Until a TFLite file exists, on-device latency is **not measured** (the live camera overlay shows 0 ms or conversion time only, with a REQUIRES MODEL banner). After install, the camera HUD prints the interpreter `latencyMs`.
