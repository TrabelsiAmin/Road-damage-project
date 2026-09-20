# WP3 Colab training guide — Agent Chaussée

## Training: NOT YET EXECUTED

This document and `training/colab/WP3_YOLOv8_training.ipynb` prepare a **Google Colab Tesla T4** run. They do **not** contain Precision, Recall, mAP, mAP50-95, F1, FPS, training time, or model size from a completed train. Those fields stay empty / `NOT_RUN` until Colab writes `training/reports/wp3/**/metrics.json` with `"status": "OK"`.

Do not copy numbers from papers into this repo. Do not train on CPU. Do not wget the 13.3 GB RDD zip from this notebook.

WP2 (D00/D10) and WP4 (D50/D60/D90) are **out of scope**. Keep three independent runners.

## Scope

| Item | Value |
| --- | --- |
| Work package | **WP3 Agent Chaussée only** |
| Classes | **0: D20** alligator crack, **1: D40** pothole |
| Depth | **None** (visual 2D) |
| Not in this run | WP2 D00/D10, WP4 D50/D60/D90 |
| YAML | `training/config/pavement.yaml` (do not invent paths) |
| Deploy | `pavement.tflite` as one of **three** runners |

`training/config/rdd_unified.yaml` is audit-only. Do not train a mixed 7-class detector for the phone.

## Dataset

Filename-hash split, seed **42**, 70/15/15, measured in `training/reports/dataset_report.json`:

| Split | Images |
| --- | ---: |
| train | 7380 |
| val | 1581 |
| test | **1582** (fixed; do not tune on it) |
| boxes | 17160 (D20=10616 as class 0, D40=6544 as class 1) |

Repo path: `training/data/processed/pavement` with `images/{train,val,test}` and `labels/{train,val,test}`.

**JPEGs are gitignored.** A fresh clone will not contain the split. Recover data with one of:

1. **Google Drive** — zip only the processed pavement folder (not the 13.3 GB dump):

```bash
cd training/data/processed
zip -r pavement_wp3_splits.zip pavement
# Upload pavement_wp3_splits.zip to Drive, then unzip in the notebook.
```

2. **Already-extracted RDD** on the machine (never auto-download):

```bash
cd training
python -m src.convert_rdd_voc --source <RDD_EXTRACT> --output data/rdd_yolo
python -m src.prepare_dataset --source data/rdd_yolo --output data/processed \
  --class-map config/source-class-map.json --seed 42
```

If counts differ from 7380/1581/1582 after restore, **stop**. Do not re-split a correct folder.

Verify:

```bash
cd training
python -m src.verify_wp3_dataset --root data/processed/pavement --yaml config/pavement.yaml
```

## Config

| Key | Value |
| --- | --- |
| Data YAML | `training/config/pavement.yaml` |
| `path` | `data/processed/pavement` (Colab rewrites this to an absolute dir) |
| names | `0: D20`, `1: D40` |
| Augmentation | `training/config/augmentation.yaml` |
| Baseline recipe | `training/config/baseline.yaml` (YOLOv8n, 640, 100, SGD, lr0=0.01, batch 16) |

## T4 hardware

| Item | Value |
| --- | --- |
| Target | Google Colab **Tesla T4**, ~15 GB VRAM |
| Batch | **16** (documented default) |
| OOM fallback | **8** (retry once; never CPU) |
| Runtime | Colab → Runtime → Change runtime type → **GPU (T4)** |
| Stop message | `CUDA GPU required for WP3 training.` |

`nvidia-smi` and `torch.cuda.is_available()` must both succeed before any `model.train`. Do not pass `--allow-cpu`.

## Commands (Colab / CUDA machine)

```bash
cd training
pip install -r requirements.txt   # repo training deps only
python -m src.verify_wp3_dataset --root data/processed/pavement --yaml config/pavement.yaml
python -m src.train --agent pavement --data config/pavement.yaml \
  --weights yolov8n.pt --epochs 100 --imgsz 640 --seed 42 \
  --optimizer SGD --lr0 0.01 --name wp3_baseline --t4-safe
python -m src.eval_wp3 --weights runs/wp3_baseline/weights/best.pt \
  --data config/pavement.yaml --split test --imgsz 640 \
  --output reports/wp3/baseline/metrics.json
python -m src.eval_small_objects --root data/processed/pavement --split test \
  --output reports/wp3/baseline/small_objects.json
python -m src.train --agent pavement --data config/pavement.yaml \
  --weights yolov8s.pt --epochs 100 --imgsz 640 --seed 42 \
  --optimizer SGD --lr0 0.01 --name wp3_expB_s640 --t4-safe
python -m src.eval_wp3 --weights runs/wp3_expB_s640/weights/best.pt \
  --data config/pavement.yaml --split test --imgsz 640 \
  --output reports/wp3/wp3_expB_s640/metrics.json
python evaluation/compare_wp3_models.py \
  --baseline reports/wp3/baseline/metrics.json \
  --improved reports/wp3/wp3_expB_s640/metrics.json \
  --output reports/wp3/compare.json
python -m evaluation.select_wp3_best \
  --candidate wp3_baseline reports/wp3/baseline/metrics.json runs/wp3_baseline/weights/best.pt \
  --candidate wp3_s640 reports/wp3/wp3_expB_s640/metrics.json runs/wp3_expB_s640/weights/best.pt \
  --dest reports/wp3/artifacts/best.pt
python -m src.export --weights reports/wp3/artifacts/best.pt --agent pavement \
  --output reports/wp3/export --precision float16
python -m src.verify_tflite --model reports/wp3/export/pavement.tflite --agent pavement
python -m src.pack_wp3_artifacts --stage reports/wp3/artifacts \
  --selected-best reports/wp3/artifacts/best.pt
```

Ultralytics writes `best.pt`, `last.pt`, `results.csv`, plots, confusion matrix, and PR curves under `runs/wp3_baseline/` when the baseline actually runs.

## Experiments

| ID | Model | imgsz | Epochs | Seed | Optimizer | lr0 | Batch | Same test set |
| --- | --- | ---: | ---: | ---: | --- | ---: | ---: | --- |
| Baseline | YOLOv8n | 640 | 100 | 42 | SGD | 0.01 | 16 (OOM→8) | test 1582 |
| Improvement | YOLOv8s | 640 | 100 | 42 | SGD | 0.01 | 16 (OOM→8) | **same** test 1582 |

Optional YOLOv8s/960 only if `nvidia-smi` shows enough free VRAM after the 640 runs. Compare **measured** JSON only (`src.eval_wp3` + `evaluation/compare_wp3_models.py`). Do not declare a winner from parameter count.

Selection (`evaluation/select_wp3_best.py`): D40 AP50, then D20 AP50, then mAP50, then smaller checkpoint. Copy the winner to `reports/wp3/artifacts/best.pt`.

## Limitations

- Detector metrics are **NOT YET EXECUTED** on this branch (no CUDA in the training VM).
- Prepared JPEGs are gitignored; Colab must mount Drive or convert an already-extracted RDD.
- This notebook must **not** wget `RDD2022_released_through_CRDDC2022.zip` (13.3 GB).
- Knowledge distillation (`src.distill`) is a stub (`metrics: null`) until a teacher checkpoint exists.
- TFLite is exported only from a real `best.pt`. File existence is not on-device validation.
- D40 small-object behaviour is a **hypothesis** until per-class AP exists in eval JSON.
- WP2 and WP4 stay separate datasets and TFLite runners.

## Next steps

1. Open `training/colab/WP3_YOLOv8_training.ipynb` on Colab GPU (T4) and run top to bottom.
2. Commit **JSON reports** (not `*.pt` / `*.tflite` / `runs/` / dataset zip).
3. Update `training/reports/METRICS.md` only by copying values from `metrics.json` where `status` is `OK`.
4. After a real `pavement.tflite` passes `src.verify_tflite --agent pavement`, consider a device smoke test (still not claimed here).
5. Only then: teacher / KD / WP2 cracks / WP4 surface.

## Notebook

Open `training/colab/WP3_YOLOv8_training.ipynb` in Colab, set runtime to **GPU (T4)**, run top to bottom.

1. Env + GPU (Python, `nvidia-smi`, PyTorch CUDA). `pip install -r training/requirements.txt` only. Stop without CUDA.
2. Repo/branch check; `pavement.yaml` names 0:D20 1:D40; reports; processed splits.
3. Dataset verify (D20/D40 only, 7380/1581/1582 if images present). Drive or convert — never wget 13.3 GB.
4. Confirm YOLO YAML is `training/config/pavement.yaml`.
5. Baseline YOLOv8n / 640 / 100 / seed 42 / SGD / lr0=0.01 / batch 16→8 → `runs/wp3_baseline/`.
6. Eval **fixed test** only; P/R/mAP50/mAP50-95 + D20/D40 from Ultralytics JSON.
7. Small-object analysis (especially D40); measured vs hypotheses.
8. Improvement: YOLOv8s / 640 on the **same** test set; compare measured only.
9. Best-model selection from criteria; save `best.pt`.
10. TFLite only if a real `best.pt` exists; do not claim mobile validated.
11. Artefact dir (best.pt, results.csv, metrics, plots, confusion, PR, tflite if any, config). Zip optional.
12. This document — training remains **NOT YET EXECUTED** until the GPU cells complete.

`src.train` still refuses CPU for `--agent pavement` with the same stop message. Do not pass `--allow-cpu` on Colab.
