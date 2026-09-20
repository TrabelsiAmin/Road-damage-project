# Metrics

STATUS: **NOT RUN** (detector). Dataset conversion **measured**.

No YOLOv8 training or validation has been executed. `src.train` refused CPU (`nvidia-smi` missing, torch/ultralytics not installed). `src.evaluate` wrote `reports/pavement_baseline_test.json` with `status: NOT_RUN` and `metrics: null`. Fine-tune / KD / TFLite export are also **NOT RUN**.

Do not add fabricated Precision / Recall / mAP tables here.

Dataset measurements (VOC XML + YOLO convert + filename-hash splits) are in `dataset_report.json`, `rdd_voc_analysis.json`, and `rdd_yolo_analysis.json`.
