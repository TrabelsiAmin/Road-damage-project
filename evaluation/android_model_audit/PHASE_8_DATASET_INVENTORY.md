# Phase 8 dataset inventory

HEAD: `cd7d16898465174c06a1362953c052f156e0485b`. Counts below were taken in this phase. Older reports are cited only as files that exist, not as measurements.

The clone is a partial clone (`blob:none`) with sparse checkout. `Global_Potholes_Dataset-image/**` is excluded, then a small allow-list is checked out. `git ls-files` sees the index. Most JPEG bytes are not in the working tree.

## 1. TFLite models

| Path | Bytes | SHA-256 | Match to Phase 6 |
| --- | ---: | --- | --- |
| `app/assets/models/road_damage.tflite` | 44,768,844 | `830f99bd8c31c5d24138c16db7862dfb62293b96cc1dec241c36140bff8a813f` | VERIFIED, identical |
| `app/assets/models/road_damage_roadsense.tflite` | 37,347,282 | `300798be883a7003a1a20f3d13757f9338a8cbec5e0ece9f990a2a5179286ccb` | VERIFIED, identical |

No other `.tflite` files are tracked. Host load with `ai_edge_litert` this phase:

- `road_damage.tflite`: float32 input `[1, 640, 640, 3]`, output `[1, 8, 8400]`
- `road_damage_roadsense.tflite`: float32 input `[1, 3, 640, 640]`, output `[1, 9, 8400]`

Embedded text found with `strings`: `YOLOv8_Small_RDD` in the legacy file. The RoadSense file contains Ultralytics graph names including `A2C2f`. Neither file contains a class-name list. A `D20` byte sequence in the legacy file sits in non-text binary and is not a label.

## 2. Training checkpoints

No `.pt`, `.onnx`, `.pth`, `.ckpt`, `.pb`, or `.weights` files are tracked or present on disk outside the two TFLite files. `training/config/model-bundles.json` names `cracks.onnx`, `pavement.onnx`, and `surface.onnx` with sha256 `REPLACE_AFTER_EXPORT`. Those files are missing. `training/data/` does not exist. Status of checkpoints: VERIFIED absent.

## 3. Images and annotations

Git index, `git ls-files`:

| Location | Count | Notes |
| --- | ---: | --- |
| `Global_Potholes_Dataset-image/**` `.jpg` | 29,120 | only extension in that tree |
| non-JPEG files in that tree | 0 | |
| YOLO `.txt`, COCO `.json`, VOC `.xml`, or `.csv` annotations anywhere in the index | 0 | XML/JSON/TXT hits are app, dashboard, and config files, not boxes |
| Working tree JPEGs in `Global_Potholes_Dataset-image/images` | 200 | sparse-checkout allow-list |
| `inference_results/*.jpg` | 9 | generated pictures, not a dataset |
| `app/test/goldens/images` | 6 JPEG | Flutter fixtures |

Full-dataset byte size: NOT MEASURED. The blobs are not local. Fetching them was stopped. The 200 checked-out files sum to 9,064,354 bytes (min 9,309, max 193,559).

## 4. Manifests and audit files

| Path | What it is |
| --- | --- |
| `training/manifests/global_potholes_manifest.json` | Says image_count 29,120, annotation_status `UNLABELED`, source path `C:\manus\TariqMap\Global_Potholes_Dataset-image`, dated 2026-09-19. The count matches this phase's index count. The Windows path is provenance text, not a file on this machine. |
| `training/reports/global_potholes_audit.json` | Same date. UNLABELED. Duplicate sample of 200 with 0 duplicates. Dimensions skipped because Pillow was missing then. |
| `evaluation/android_model_audit/label_validation.json` | BLOCKED, image_count 200, label_file_count 0. That 200 is the working tree, not the index. |
| `evaluation/android_model_audit/METRICS.json` | Earlier audit. `map50` and `map50_95` are null. |
| `dashboard/src/data/validation_metrics.json` | Hardcoded dashboard copy. Not a measurement from this phase. Not used as a result. |
| `docs/dataset-audit.md` | Claims D00 1,245, D10 890, D20 3,450, D40 12,055 and "45 images" missing labels. Contradicted by zero annotation files in the index and by the JSON audit. NOT VERIFIED. |
| `docs/ml-evaluation.md` | Requirements for a future RDD release. It does not record a URL, checksum, or license for a dataset that is in the repo. |

## 5. Class-name definitions

See `PHASE_8_CLASS_MAPPING_ANALYSIS.md`. Short list: Flutter `D00/D10/D20/D40`, Python `test_images.py` `Crack/Pothole/Rutting/Uneven-Surface`, YAML agent names under `training/config/`, and `training/config/source-class-map.json`.

## 6. Evaluation scripts

| Script | Role |
| --- | --- |
| `training/src/audit_dataset.py` | Counts images and annotation files. Exit 1 when unlabeled. |
| `evaluation/android_model_audit/scripts/spec_decoder_math.py` | Numeric mirror of the legacy decoder tests. Not a dataset metric. |
| `evaluation/android_model_audit/scripts/evaluate_readiness.py` | Added this phase. Loads TFLite shapes and exits `NOT EVALUABLE` with `metrics: null`. |
| `test_images.py` | Ad-hoc viewer. Its class strings are marked unproven in the file. It was not used to score anything. |

## 7. Provenance

Verified: the only image collection in git is `Global_Potholes_Dataset-image/images/*.jpg`, flat, no license file, no train/val/test directories. The manifest records a Windows path and the date 2026-09-19. README text calls the bundled model an RDD2022 4-class model. That sentence is a claim in the README, not a stored training export. No RDD archive, URL, or label export is in the repo. Status of external provenance: NOT VERIFIED.
