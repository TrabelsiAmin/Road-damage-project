# Dataset

## Two datasets, two roles

### 1. Global Potholes (`Global_Potholes_Dataset-image`)

| Field | Value |
| --- | --- |
| Status | **DEMO/REFERENCE** |
| Images | 29,120 JPEG (from the original import) |
| Labels | **None** |
| Train? | **No** |
| In git? | **No** (gitignore; untracked after this branch) |

The Phase 1 audit JSON (`training/reports/global_potholes_audit.json`) is the source of truth: `annotation_status: UNLABELED`. Older prose that listed D00/D10/D20/D40 instance counts for this dump was **incorrect** and has been removed.

Until someone annotates those photos, they must not enter `src.train`.

### 2. RDD2022 / RDD2024 (labeled)

| Field | Value |
| --- | --- |
| Status | **REQUIRES LABELED DATA** (download locally; not vendored) |
| Source | [Figshare RDD2022](https://figshare.com/articles/dataset/RDD2022/16680289), [RoadDamageDetector](https://github.com/sekilab/RoadDamageDetector) |
| Format | Pascal VOC XML + JPEG, per-country subsets |
| Train? | **Yes**, after `src.convert_rdd_voc` |

This repository does not bundle RDD. `python -m src.download_rdd` only locates a local extract and prints the official URLs.

## TariqMap class taxonomy

| Code | Meaning | Agent | RDD mapping | Availability on RDD |
| --- | --- | --- | --- | --- |
| D00 | Longitudinal crack | cracks | D00 | expected |
| D10 | Transverse crack | cracks | D10 | expected |
| D20 | Alligator crack | pavement | D20 | expected |
| D40 | Pothole | pavement | D40 | expected |
| D50 | Faded pedestrian crossing | surface | **D44** (crosswalk blur) | only if D44 is annotated |
| D60 | Faded lane marking | surface | **D43** (white line blur) | only if D43 is annotated |
| D90 | Rutting (visual) | surface | **none** | **ABSENT** |

RDD's own `D50` in some country subsets is a catch-all "other" class. It is **not** TariqMap D50 and is excluded.

No other aliases are guessed. Unknown XML names go to `exclusion_report.json`.

## What `analyze_labeled_dataset` checks

- class names and counts
- annotation format (VOC XML vs YOLO txt)
- train/val/test split presence
- bounding-box validity
- image sizes (if Pillow is installed)
- small-object rate (pixel area < 32×32)

Run it on the converted RDD folder **before** training. If D50/D60/D90 are missing, the surface agent cannot be trained honestly — leave it on mock.

## Splits

`prepare_dataset.py` splits by filename hash (70/15/15 by default) so adjacent video frames stay in one split. The test split is not to be used for threshold fishing.
