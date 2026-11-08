# Phase 8 implementation report

HEAD stayed `cd7d16898465174c06a1362953c052f156e0485b`. Nothing was committed or pushed. Weights were not modified. Checksums match Phase 6. No image was deleted. `ios/` was not edited. Android code was not edited.

## Added

| File | Purpose |
| --- | --- |
| `evaluation/android_model_audit/scripts/evaluate_readiness.py` | Loads a TFLite file, reports shapes, counts label files, and exits 2 with `NOT EVALUABLE` and `metrics: null` unless labels and a mapping file with `mapping_status: VERIFIED` plus non-empty `evidence` both exist. Even then it does not calculate scores. |
| `evaluation/android_model_audit/scripts/test_evaluate_readiness.py` | Three tests: the repo dataset refuses, a VERIFIED mapping without labels refuses, a YOLO file without a verified mapping refuses. Stdout must not contain score field names. |

No detection threshold, stretch function, NMS, class code, or model-selection flag was changed.

## Commands and results

| Command | Result | Versus Phase 7 |
| --- | --- | --- |
| `python3 evaluation/android_model_audit/scripts/evaluate_readiness.py` | exit 2, `NOT EVALUABLE`, metrics null, legacy shapes `[1,640,640,3]` → `[1,8,8400]` | new |
| same, `--model road_damage_roadsense.tflite` | exit 2, shapes `[1,3,640,640]` → `[1,9,8400]` | new |
| `python3 -m unittest evaluation.android_model_audit.scripts.test_evaluate_readiness` | 3 passed | new |
| `flutter analyze` | No issues found | same, clean |
| `flutter test` | 149 passed | same |
| Python unittest (contracts, API, sync, offline, SQL contract, EXIF) | 36 passed | same |
| `lock_android_contract.py` | CONTRACT OK | same |
| `spec_decoder_math.py` | SPEC MATH OK | same |
| dashboard vitest | 93 passed | same |
| dashboard `npm run build` | built | same |
| Android debug, release, AAB | NOT EXECUTED | No Android change. Not a failure. |

No test was weakened or skipped.

## Decoder and preprocessing

`spec_decoder_math.py` and the Flutter suite cover the existing stretch and decoder contracts. They passed. They are host checks. They are not mAP.
