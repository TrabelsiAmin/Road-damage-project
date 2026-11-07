# Accuracy

**NOT VERIFIED. No mAP was computed. No boxes were invented.**

## Why

A detection score needs a labeled held-out split and a stated IoU. This repository has:

- weights: two TFLite files (**VERIFIED** present)
- labels: **0** files (**VERIFIED**)
- original `.pt`: absent (**VERIFIED**)
- `validation_metrics.json`: present and imported by the dashboard, but no `results.csv`, no split, no command log (**NOT VERIFIED** as science)

Using train images as the test, or treating “the model emitted a box” as precision, would be false. Neither was done.

## Workflow added (does not touch the dataset)

| Script | What it does | What it does not do |
|---|---|---|
| `scripts/validate_yolo_dataset.py` | Counts images, checks YOLO rows (5 fields, class id, normalized cx cy w h, box inside the frame), writes JSON | Does not create, move, or delete images or labels |
| `scripts/plan_eval_manifest.py` | Writes a deterministic 200-name plan and a 70/15/15 hash split | Does not copy files and does not write boxes |

Run recorded this phase:

- Validator on the sparse checkout: **BLOCKED**, 200 files visible, labels directory missing. Full git count remains 29,120.
- Plan from all 29,120 git names, seed 20261105, n=200: train 138, val 29, test 33. File: `eval_plan_200.json`. Tag **PLAN_ONLY**.

## Protocol to follow later

1. Annotate only the 200 planned names, or a larger set, in a new labels directory. Do not overwrite JPEGs.
2. Run the validator. Proceed only if `status` is VERIFIED and `invalid_row_count` is 0.
3. Declare the class-id map in writing before scoring. Do not assume the Python script’s four English words.
4. Choose thresholds on **val** only.
5. Report mAP50 and mAP50-95 once on **test**, with the confidence and IoU used for the PR curve. Ultralytics mAP usually uses a low confidence (the repo’s `validate_models.py` defaults to 0.001) and must not be confused with the app’s 0.30–0.40 operating points.
6. Do not put those numbers in the dashboard until the command output is in the repo.

Until step 2 passes, accuracy stays **NOT VERIFIED**.
