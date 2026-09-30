# ML Evaluation and Mobile Optimization

See [evaluation.md](evaluation.md) and [training.md](training.md).

Honesty rules:

- Dataset identity, license, and class mapping must be recorded before a run.
- Split by image identity. Never tune thresholds on the final test split.
- Report precision, recall, mAP50, mAP50-95, per-class AP, confusion, small-object recall.
- A combined score must not hide a weak class (especially D00/D10/D20/D40).
- **No accuracy is claimed in this repository** until `src.evaluate` has been run on real weights.
- RDD2022 conversion/splits were measured on 2026-09-20 (`training/reports/dataset_report.json`). Detector metrics remain **NOT RUN** (no GPU).
- Knowledge distillation (`src.distill`) is a stub: it records a plan, not student mAP.
- WP3 pavement (D20/D40, small-object recall, 2D only) is the first agent on this path.
