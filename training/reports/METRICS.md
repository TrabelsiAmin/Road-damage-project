# Metrics

STATUS: **NOT RUN** (detector). Dataset conversion **measured**. WP3 Colab notebook **ready**.

No YOLOv8 training or validation has been executed. `src.train` refused CPU (`nvidia-smi` missing). `src.eval_wp3` writes `status: NOT_RUN` and `metrics: null` without weights. Fine-tune / KD / TFLite export are also **NOT RUN**.

Use `training/colab/WP3_YOLOv8_training.ipynb` on a CUDA GPU. Do not add fabricated Precision / Recall / mAP / F1 tables here.

Dataset measurements (VOC XML + YOLO convert + filename-hash splits) are in `dataset_report.json`, `rdd_voc_analysis.json`, and `rdd_yolo_analysis.json`.
