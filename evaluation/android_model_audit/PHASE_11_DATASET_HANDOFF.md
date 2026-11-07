# Phase 11 dataset handoff

Class mapping is **UNKNOWN**. Metrics stay null. `evaluate_readiness.py` exits 2 with `NOT EVALUABLE` until labels and a verified mapping both exist. Re-checked this phase: the git index has 29,120 `.jpg` files under `Global_Potholes_Dataset-image` and no other extension; 29,028 unique blobs; 92 duplicate pairs; 200 files checked out; 0 annotation files.

## What the dataset owner must supply

1. **Original source and license.** The images entered git in commit `530096993889` (`Initial project import`, 2026-09-19). The manifest path is `C:\manus\TariqMap\Global_Potholes_Dataset-image`. No URL and no license file are in the repo. A public dataset with a similar name is not this set. UUID filenames in one flat folder are not the RDD2022 country/XML layout.
2. **Original annotations.** None are in the index. `docs/dataset-audit.md` class counts are contradicted by that and are not labels. Model predictions must not be pasted in as ground truth.
3. **Original training configuration.** `training/config/augmentation.yaml` names an RDD2024 split and `yolov8s.pt`. Those artifacts are not in the repo. The yaml thresholds are not the app thresholds.
4. **Model export provenance.** Commit `30224f15` says the legacy file is the four-class checkpoint from `oracl4/RoadDamageDetection`. That repo's notebook `training/0_PrepareDatasetYOLOv8.ipynb` contains `D00=0`, `D10=1`, `D20=2`, `D40=3`. Their published file is `models/YOLOv8_Small_RDD.pt`. It was not hashed against `road_damage.tflite` (`830f99bd8c31c5d24138c16db7862dfb62293b96cc1dec241c36140bff8a813f`, 44,768,844 bytes). The embedded string `YOLOv8_Small_RDD` is not that hash. RoadSense (`300798be…`, 37,347,282 bytes) has no export log. Do not treat the notebook order as proof for these bytes.
5. **Authoritative class-index mapping.** Flutter displays index order D00, D10, D20, D40 for the legacy `[1, 8, 8400]` head. `test_images.py` uses Crack, Pothole, Rutting, Uneven-Surface in a different order. `source-class-map.json` puts rutting at D90. The mapping stays UNKNOWN until a training export or the annotation guideline records the channel order for these weights.
6. **Review and quality.** Boxes need an annotator id, provenance, and a second person's `accepted` review. Empty images need an explicit negative flag. The 92 duplicate pairs must stay in the same split.

## Tools already in the tree

| File | Role |
| --- | --- |
| `evaluation/android_model_audit/schema/annotation_schema.json` | COCO-style schema `tariqmap-annotations-1`. Category names stay pending until confirmed. It contains no real labels |
| `evaluation/android_model_audit/scripts/validate_annotations.py` | Rejects bad JSON, unknown category ids, bad boxes, missing images, missing provenance, and unreviewed boxes. It does not write next to the JPEGs |
| `evaluation/android_model_audit/scripts/assign_splits.py` | Duplicate-aware split. It refuses `Global_Potholes_Dataset-image` until a real labeled file exists, and it does not print class counts unless the caller marks annotations verified |
| `evaluation/android_model_audit/scripts/evaluate_readiness.py` | Loads tensor shapes. Returns `metrics: null` and exit 2 while ground truth or the mapping is missing. A candidate schema is not verified ground truth |

Both TFLite files stay bundled. Default load is `road_damage.tflite`. RoadSense loads only when `USE_ROADSENSE_MODEL` is set, and that path also loads the legacy file for D40.
