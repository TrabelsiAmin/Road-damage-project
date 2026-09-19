# ML Evaluation and Mobile Optimization

See [evaluation.md](evaluation.md) and [training.md](training.md).

Honesty rules:

- Dataset identity, license, and class mapping must be recorded before a run.
- Split by image identity. Never tune thresholds on the final test split.
- Report precision, recall, mAP50, mAP50-95, per-class AP, confusion, small-object recall.
- A combined score must not hide a weak class (especially D00/D10/D20/D40).
- **No accuracy is claimed in this repository** until `src.evaluate` has been run on real weights.
