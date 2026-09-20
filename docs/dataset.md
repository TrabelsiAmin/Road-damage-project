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
| Status | **CURRENTLY ON DISK** in the 2026-09-20 training VM (not vendored in git) |
| Source | [Figshare article 21431547](https://figshare.com/articles/dataset/RDD2022_-_The_multi-national_Road_Damage_Dataset_released_through_CRDDC_2022/21431547) |
| Zip | `RDD2022_released_through_CRDDC2022.zip` **13,264,172,619 bytes** (size verified after wget) |
| Layout | Outer zip = 7 country zips. VOC XML under `Country/train/annotations/xmls` + `train/images`. Unlabeled `test/images` in some countries |
| Train? | **Yes**, after `src.convert_rdd_voc`. Detector training on this VM: **NOT RUN** (no GPU) |

Machine-readable source of truth: `training/reports/dataset_report.json`.

### Measured extract (2026-09-20)

Parsed **every** VOC XML (38,385 files, 0 parse errors). Image files on disk: **47,420** (matches the official File_List). Unlabeled test JPEGs: **9,035**. XML with no `<object>`: **11,724**.

| Raw XML name | Count | TariqMap mapping |
| --- | ---: | --- |
| D00 | 26,016 | D00 longitudinal crack |
| D10 | 11,830 | D10 transverse crack |
| D20 | 10,617 | D20 alligator (1 degenerate box dropped → 10,616) |
| D40 | 6,544 | D40 pothole |
| D44 | 5,057 | **D50** faded pedestrian crossing |
| D43 | 793 | **D60** faded lane marking |
| D50 | 3,581 | **EXCLUDED** (RDD “other”, not TariqMap D50) |
| Repair | 1,046 | EXCLUDED |
| D01 | 179 | EXCLUDED |
| D11 | 45 | EXCLUDED |
| Block crack | 3 | EXCLUDED |
| D0w0 | 1 | EXCLUDED |
| D90 | **0** | **ABSENT** |

Converted YOLO set: **25,642** labeled images (hardlinked), **0** missing images, **60,856** mapped boxes. One MD5 duplicate pair removed (`United_States_003917.jpg` / `United_States_001623.jpg`).

Filename-hash splits 70/15/15 (seed 42), then `validate_dataset.py`:

| Agent | Images | train / val / test | Boxes in agent labels |
| --- | ---: | --- | ---: |
| cracks (D00, D10) | 16,939 | 11,857 / 2,540 / 2,542 | 37,842 |
| pavement (D20, D40) | 10,543 | 7,380 / 1,581 / 1,582 | 17,160 |
| surface (D50, D60, D90) | 4,708 | 3,295 / 706 / 707 | 5,850 (D90 = 0) |

BBox stats (valid VOC boxes): pixel area min 6, mean ~26,925, max ~1,005,172. Image sizes 512–4040 × 512–2044. Small objects (<32×32 px): **7.91%** of VOC boxes; **20.22% of D40** (highest among mapped classes). Two degenerate boxes skipped.

Country XML counts match the File_List: China_Drone 2,401; China_MotorBike 1,977; Czech 2,829; India 7,706; Japan 10,506; Norway 8,161; United_States 4,805.

## TariqMap class taxonomy

| Code | Meaning | Agent | RDD mapping | Availability on RDD |
| --- | --- | --- | --- | --- |
| D00 | Longitudinal crack | cracks | D00 | expected |
| D10 | Transverse crack | cracks | D10 | expected |
| D20 | Alligator crack | pavement | D20 | expected |
| D40 | Pothole | pavement | D40 | expected |
| D50 | Faded pedestrian crossing | surface | **D44** (crosswalk blur) | **PRESENT** (5,057 boxes) |
| D60 | Faded lane marking | surface | **D43** (white line blur) | **PRESENT** (793 boxes) |
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

Run it on the converted RDD folder **before** training. D50 and D60 **are present** on this dump (from D44/D43). D90 is still missing, so a surface head that includes D90 has no positives for rutting.

## Splits

`prepare_dataset.py` splits by filename hash (70/15/15 by default) so adjacent video frames stay in one split. The test split is not to be used for threshold fishing.
