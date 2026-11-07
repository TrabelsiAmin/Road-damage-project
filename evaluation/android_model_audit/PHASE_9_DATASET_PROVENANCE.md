# Phase 9 dataset provenance

HEAD `cd7d16898465174c06a1362953c052f156e0485b`. The local clone is shallow (`git rev-parse --is-shallow-repository` is true). Its one local commit message is `Fix Leaflet map layout and rendering`. GitHub history was read with the commits API. No image bytes were downloaded.

Phase 8 counts were rechecked: index `29,120` `.jpg` and `0` other files under `Global_Potholes_Dataset-image`; working tree `200` files; `29,028` unique blob ids; `92` duplicate groups. Annotation files remain zero.

## Where the JPEGs came from

| Evidence | What it says | Status |
| --- | --- | --- |
| GitHub commits for path `Global_Potholes_Dataset-image` | One commit: `530096993889a22f753056558324713284779ff9`, 2026-09-19, message `Initial project import`. https://github.com/TrabelsiAmin/Road-damage-project/commit/530096993889a22f753056558324713284779ff9 | VERIFIED as the introducing commit. The message body is only that title. |
| `training/manifests/global_potholes_manifest.json` | `source_path` `C:\manus\TariqMap\Global_Potholes_Dataset-image`, `image_count` 29120, `annotation_status` `UNLABELED`, `audit_date_utc` `2026-09-19T12:26:57.862439+00:00` | VERIFIED as a file in the repo. The Windows path is not on this machine. |
| `training/reports/global_potholes_audit.json` | Same path and date. `annotation_files_found` empty. `license`: `No license file found in dataset root`. | VERIFIED |
| `test_single_image.py` | Hardcoded `C:\manus\TariqMap\Global_Potholes_Dataset-image\images\0a90c98c-345f-4a1a-a5a7-26010f1d356f.jpg` | VERIFIED as a local path string |
| README, docs, configs | No URL for this image folder | VERIFIED absence |
| Filenames | UUID stems in one flat `images/` directory | VERIFIED |

Official public source of these 29,120 files: **not identified**. A dataset with a similar name was not treated as this one, and no replacement was downloaded.

## Annotations upstream

Not recovered. The introducing commit's tree, as stored in this repo's index, has only `.jpg` files. The audit JSON says unlabeled. `docs/dataset-audit.md` class counts remain contradicted by that and are not evidence.

## Training export and class config

| Item | Evidence | Status |
| --- | --- | --- |
| `road_damage.tflite` added | Commit `30224f15fb9e9683bfd608507ed456d66cdaa7dc`, 2026-09-23, `Use RoadDamageDetection model on device`. https://github.com/TrabelsiAmin/Road-damage-project/commit/30224f15fb9e9683bfd608507ed456d66cdaa7dc . The commit records sha256 `830f99bd8c31c5d24138c16db7862dfb62293b96cc1dec241c36140bff8a813f`, which still matches the file. | VERIFIED |
| Author comment at that commit, `app/lib/services/model_manager.dart` lines 7–8 | `The four-class checkpoint from oracl4/RoadDamageDetection, exported for phone-side inference.` That comment is not in the current file. | VERIFIED as historical text |
| Upstream README | https://github.com/oracl4/RoadDamageDetection says the app uses YOLOv8 trained on the CRDDC 2022 dataset and lists Longitudinal Crack, Transverse Crack, Alligator Crack, Potholes. It points dataset download at https://github.com/sekilab/RoadDamageDetector (`RDD2022.zip`), with country folders and VOC xml. | VERIFIED as that repo's README. Not evidence that our UUID JPEGs are that archive. |
| Upstream notebook `training/0_PrepareDatasetYOLOv8.ipynb` | Contains `"D00": 0`, `"D10": 1`, `"D20": 2`, `"D40": 3` and comments `0: D00 > Longitudinal Crack` through `3: D40 > Potholes`. | VERIFIED as that notebook's text. The published weight there is `models/YOLOv8_Small_RDD.pt` (89,569,358 bytes). Our file is a TFLite export whose embedded string is `YOLOv8_Small_RDD`. The `.pt` was not downloaded and was not hashed. |
| `road_damage_roadsense.tflite` | GitHub path history: commit `c080c00215eb`, 2026-10-12, `config: add RoadSense hybrid feature flags and register model asset`. No export log in-tree. | PARTIALLY VERIFIED (commit only) |
| `training/config/augmentation.yaml` | Says thresholds were tuned on an RDD2024 validation split and notes `yolov8s.pt`. Those artifacts are not in the repo. The yaml values (D20 0.28, D40 0.42) are not the app thresholds. | NOT VERIFIED as a training run |
| Removed `backend/roboflow.py` at parent `262ffccbfebd94d6c29090b56987753d627eb4df` | StreetSense adapter for hosted model `road-damage-detection-apxtk/5`, with a natural-language map (longitudinal crack → D00, pothole → D40, rutting → D90). Deleted in `30224f15`. | VERIFIED as deleted adapter text. It is not a label file and not the TFLite channel order. |

## Unknowns

- Who captured the UUID JPEGs, and under what license.
- Whether any label archive existed beside `C:\manus\TariqMap\...` and was never committed.
- Whether `road_damage.tflite` is an export of `oracl4` `YOLOv8_Small_RDD.pt`.

Evaluation remains blocked. No score was computed.
