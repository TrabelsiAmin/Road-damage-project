# Phase 8 evaluation feasibility

Model evaluation did not run. No precision, recall, F1, mAP@0.5, or mAP@0.5:0.95 was calculated.

## Why it cannot run

A valid labeled dataset is not in this repo.

| Requirement | State |
| --- | --- |
| Images | 29,120 JPEG paths in the git index. 200 bytes are checked out. |
| Ground truth | 0 annotation files. |
| Class mapping tied to these weights | UNKNOWN. See the class-mapping report. |
| Train/val/test split | Not present. Leakage cannot be checked. |
| Provenance of the images | A Windows path and a September 2026 audit JSON. No license, no RDD URL, no checksum of a public release. |
| Checkpoints other than the two TFLite files | Missing. |
| Stored metrics | `validation_metrics.json` is hardcoded. `METRICS.json` already stores null mAP. `docs/dataset-audit.md` counts are contradicted by the missing labels. None of those are results. |

Status: BLOCKED.

## What would be required

Minimum before any score is meaningful:

1. A label file per evaluated image, or an explicit negative label, in YOLO, COCO, or VOC, with a parser that rejects bad boxes and unknown class ids.
2. A written mapping from those class ids to the four legacy output channels and, separately, to the five RoadSense channels. The mapping has to come from the training export or from the annotation guideline used to create the labels. A guessed order is not enough.
3. A held-out test split keyed by image identity, with the 92 exact duplicate pairs kept on the same side of the split.
4. Inference that uses the current stretch-to-640 path and the current decoder and thresholds (D00/D10 0.35, D20 0.30, D40 0.40, IoU 0.45). Letterbox stays off for the legacy model.
5. Sample counts, the threshold table, and the model SHA-256 printed next to any metric.
6. RoadSense scored only on a build with `USE_ROADSENSE_MODEL`, and the legacy D40 head scored on that path as well, because that is how the app loads it.

Until then the scientific status stays NOT VERIFIED.

## What this phase did load

`evaluate_readiness.py` loaded both TFLite files, checked the shapes above, found 0 label files under the working-tree dataset, and printed `status: NOT EVALUABLE` with `metrics: null`. Exit code 2. That is a gate, not an evaluation.
