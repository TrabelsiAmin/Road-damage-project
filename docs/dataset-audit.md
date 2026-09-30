# TariqMap Dataset Audit

**Date**: 2026-09-20  
**Strategy**: Option A — do not train on unlabeled images.

## Global Potholes dump

Source of truth: `training/reports/global_potholes_audit.json`

| Field | Value |
| --- | --- |
| Path (original import) | `Global_Potholes_Dataset-image` |
| Image count | **29,120** JPEG |
| Annotation files | **0** |
| Annotation status | **UNLABELED** |
| Class mapping | **NOT POSSIBLE** |
| Train/val/test split | **NOT PRESENT** (flat directory) |
| Verdict | **STOP** — do not train |

There are **no** D00 / D10 / D20 / D40 instance counts for this dump. Any earlier table that listed thousands of labeled cracks or potholes on Global Potholes was **wrong**: those numbers were not measured from labels because labels do not exist.

The images may still be used as unlabeled demo/reference photos in the mobile app. They are gitignored and are not part of the training pipeline.

## Labeled data for training

Use RDD2022/RDD2024 (Pascal VOC). See [dataset.md](dataset.md).

Probe recorded 2026-09-20 (`training/reports/rdd_access.json` and `dataset_report.json`):

| Field | Value |
| --- | --- |
| Figshare | article **21431547**, HTTP 200 |
| Zip | `RDD2022_released_through_CRDDC2022.zip` **13,264,172,619** bytes |
| Zip downloaded | **Yes** (wget exit 0, size matched) |
| Extract | **38,385** XML, **47,420** JPEG (matches File_List) |
| Official label_map.pbtxt | D00, D10, D20, D40 only (XML also has D43/D44) |

Detector metrics on this machine:

- baseline mAP: **not computed** (no GPU; `src.train` refused CPU)
- per-class AP: **not computed**
- confusion matrix: **not computed**

Do not copy numbers from other papers and present them as this project's results.

## Mock fallback (application)

The Flutter app can run gallery import with a deterministic mock runner. That is **DEMO/MOCK**, labeled in the UI. Video and live camera refuse mock boxes (`allowMock: false`) so a missing model cannot look like a detector.
