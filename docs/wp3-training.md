# WP3 Colab training guide — Agent Chaussée

## Training: NOT YET EXECUTED

This document and `training/colab/WP3_YOLOv8_training.ipynb` prepare a **Google Colab GPU** run. They do **not** contain Precision, Recall, mAP, F1, FPS, training time, or model size from a completed train. Those fields stay empty / `NOT_RUN` until Colab writes `training/reports/wp3/**/metrics.json` with `"status": "OK"`.

Do not copy numbers from papers into this repo.

## Scope

| Item | Value |
| --- | --- |
| Work package | **WP3 Agent Chaussée only** |
| Classes | **D20** alligator crack, **D40** pothole |
| Depth | **None** (visual 2D) |
| Not in this run | WP2 D00/D10, WP4 D50/D60/D90 |
| Deploy | `pavement.tflite` as one of **three** runners |

`training/config/rdd_unified.yaml` is audit-only. Do not train a mixed 7-class detector for the phone.

## Dataset (already split — do not recreate)

Filename-hash split, seed **42**, 70/15/15, measured in `training/reports/dataset_report.json`:

| Split | Images |
| --- | ---: |
| train | 7380 |
| val | 1581 |
| test | **1582** (fixed; do not tune on it) |
| boxes | 17160 (D20=10616 as class 0, D40=6544 as class 1) |

Repo path: `training/data/processed/pavement` with `images/{train,val,test}` and `labels/{train,val,test}`.

**JPEGs are gitignored.** Colab must get the folder from Drive, `rsync`, or a zip you build locally:

```bash
# On the machine that already has the processed split (do NOT zip the 13 GB RDD dump)
cd training/data/processed
zip -r pavement_wp3_splits.zip pavement
# Upload pavement_wp3_splits.zip to Google Drive, then unzip in the notebook.
```

YAML: `training/config/pavement.yaml` (`path: data/processed/pavement`, names `0: D20`, `1: D40`). The notebook rewrites `path` to an absolute directory for Colab.

Verify (must pass before train):

```bash
cd training
python -m src.verify_wp3_dataset --root data/processed/pavement --yaml config/pavement.yaml
```

If counts differ from 7380/1581/1582, **stop**. Restore the original split. Do not run `prepare_dataset.py` again.

## Notebook

Open `training/colab/WP3_YOLOv8_training.ipynb` in Colab, set runtime to **GPU**, run top to bottom.

1. Install ultralytics / torch  
2. **STOP** if CUDA is missing (`CUDA GPU required for WP3 training.`) — no CPU fallback  
3. Locate pavement split  
4. `verify_wp3_dataset`  
5. Ground-truth small-object bins (`eval_small_objects`)  
6. Point YOLO at `pavement.yaml`  
7. Baseline YOLOv8n, imgsz 640, seed 42, 100 epochs, `runs/wp3_baseline/`  
8. Eval on the **test** split → `reports/wp3/baseline/`  
9. Experiments A (n/640), B (s/640), C (higher imgsz if VRAM allows)  
10. Optional fine-tune of the justified winner → `reports/wp3/final/`  
11. `evaluation/compare_wp3_models.py` — declares “better” only from real JSON  
12. KD via `src.distill` **stub** (`metrics: null` until a teacher exists)  
13. `src.export` + `src.verify_tflite --agent pavement`  
14. Zip artefacts **without** the dataset (`src.pack_wp3_artifacts`)

`src.train` still refuses CPU. Do not pass `--allow-cpu` on Colab.

## After Colab

Commit **JSON reports and docs**, not `*.pt` / `*.tflite` / `runs/` / the zip. Update `training/reports/METRICS.md` only with values copied from `reports/wp3/**/metrics.json` when `status` is `OK`.
