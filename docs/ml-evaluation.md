# ML Evaluation and Mobile Optimization

## Dataset discipline

The exact RDD2024/NRDD2024 release must be recorded with its source URL, checksum, license, class names, country distribution, and annotation format. Split by image identity and preserve a final test set that is never used for threshold tuning. Because RDD images lack phone capture metadata, metadata generation remains a WP1 responsibility and must not be fabricated in the training set.

## Per-agent evaluation

Report precision, recall, mAP50, mAP50-95, and per-class confusion for each agent. Add small-object recall, false positives per image, and latency on the target phone. Report confidence threshold and NMS IoU with every result. A combined score must never hide a weak agent or class.

## Robustness set

Create a small manually reviewed Tunisian validation set with day/night, shadows, rain, camera tilt, motion blur, different road materials, and phone-camera variation. Use it as a qualitative demo set and a regression gate. Include negative images without damage.

## Threshold policy

Start with agent-specific thresholds selected on validation data. Use calibration curves or reliability diagrams to decide whether confidence can support prioritization. Confidence is evidence quality, not physical severity. Let the actor confirm priority.

## Compression ladder

Train a small YOLO student, export float32, benchmark it, then test float16 and int8. Compare accuracy, model size, RAM, cold start, and per-image latency on the real device. Keep the best model that meets the demo’s accuracy floor. Every export gets a checksum and manifest entry.

## Acceptance gates

A candidate bundle is shippable only if it passes: class-contract validation, model-load test, non-empty output test, coordinate-range test, checksum validation, per-agent latency test, and a human review of annotated examples. Do not claim trained accuracy until the final test split has been evaluated.
