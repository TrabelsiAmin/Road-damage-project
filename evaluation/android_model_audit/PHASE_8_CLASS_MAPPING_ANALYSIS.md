# Phase 8 class mapping

Mapping between `Crack` / `Pothole` / `Rutting` / `Uneven-Surface` and `D00` / `D10` / `D20` / `D40` is **UNKNOWN**. No mapping is proposed.

## What each side actually says

| Source | Indices or names | What it proves |
| --- | --- | --- |
| `app/lib/services/tflite_agent_runner.dart` `_classNames` | 0 D00, 1 D10, 2 D20, 3 D40 | The Android display contract. The comment in that file says this is not proven equal to the Python strings. |
| `app/lib/inference/legacy_decoder.dart` | 4 box channels + 4 class channels, shape `[1, 8, 8400]` | Layout the legacy decoder accepts. Host load this phase matched that shape. |
| `app/lib/inference/roadsense_decoder.dart` | 0 D00, 1 D10, 2 D20, 3 D40, 4 Repair. Shape `[1, 9, 8400]` | Code names for the optional model. Host load matched NCHW `[1, 3, 640, 640]` → `[1, 9, 8400]`. The names are not in the file's metadata. |
| `test_images.py` `CLASS_NAMES` | 0 Crack, 1 Pothole, 2 Rutting, 3 Uneven-Surface | A display list. The file says these strings are unproven against D00–D40. |
| `training/config/source-class-map.json` | D00 longitudinal, D10 transverse, D20 alligator, D40 pothole, plus D50, D60, D90 rutting | An alias policy for a future labeled export. Rutting is D90 here, not one of the four Python names' indexes. |
| `training/config/cracks.yaml` | 0 D00, 1 D10 | Intended names for a missing `data/processed/cracks` tree. |
| `training/config/pavement.yaml` | 0 D20, 1 D40 | Same, for a missing pavement tree. |
| `training/config/surface.yaml` | 0 D50, 1 D60, 2 D90 | Same, for a missing surface tree. |
| `app/assets/models/model-bundles.json` | agent `road_damage` classes D00, D10, D20, D40, sha256 of the legacy file | Bundle manifest. It does not include RoadSense or the Python names. |
| TFLite metadata | `YOLOv8_Small_RDD` in the legacy file. No names list in either file. | Architecture tag only. |

## Why a mapping is not proposed

Index order does not agree across the two name lists. Python index 1 is `Pothole`. Flutter index 1 is `D10` (transverse crack). Python index 2 is `Rutting`. Flutter index 2 is `D20` (alligator). `source-class-map.json` puts rutting at D90, which is not one of the four legacy channels. Using either order as ground truth would invent a correspondence.

There are no source annotations in this repo to check against either list. `docs/dataset-audit.md` states instance counts for D00–D40. Those counts are not backed by a label file. They are NOT VERIFIED and were not used.

`dashboard/src/data/validation_metrics.json` pairs D-codes with names and with numeric scores. That file is static dashboard content. It is not a confusion matrix from this dataset. The numbers were not treated as results.

## Channel layout, separate from names

These shapes were loaded this phase and match the code gates. They do not identify classes:

| Model | When it loads | Input | Output | Class channels in code |
| --- | --- | --- | --- | --- |
| `road_damage.tflite` | default | NHWC `[1, 640, 640, 3]` | `[1, 8, 8400]` | 4, named D00 D10 D20 D40 by the app |
| `road_damage_roadsense.tflite` | only `USE_ROADSENSE_MODEL` | NCHW `[1, 3, 640, 640]` | `[1, 9, 8400]` | 5, named D00 D10 D20 D40 Repair by the app |

Selection behavior was not changed. The hybrid path still also loads the legacy file for D40 when `USE_POTHOLE_MODEL_FOR_D40` is true (its default).

## Missing evidence

- A training config or export log that lists the class index order stored in `road_damage.tflite`.
- The same for `road_damage_roadsense.tflite`, including whether channel 7 is Repair.
- Label files whose class ids were produced for those exact weights.
- A statement, outside this repo's own comments, that ties `YOLOv8_Small_RDD` to a specific RDD label map and to these bytes.

Until those exist, the mapping status is NOT VERIFIED.
