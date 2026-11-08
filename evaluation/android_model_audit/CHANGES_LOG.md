# Changes log

No commit. No push. Weights, datasets, and Supabase were not modified.

Backups (copies, originals kept) are in `evaluation/android_model_audit/backups/`:

- `tflite_agent_runner.dart`
- `preprocessing.dart`
- `test_images.py`
- `test_single_image.py`

## Source edits

| File | Why |
|---|---|
| `app/lib/inference/preprocessing.dart` | Added `stretchToModelInput`. Same `copyResize` the runner already used. Letterbox was not applied to the default model because the `.pt` is missing. |
| `app/lib/inference/legacy_decoder.dart` | New. Moved the existing `[1, 8, 8400]` decode out of the runner so tests can lock it. Channel order unchanged. RoadSense `[1, 9, 8400]` is rejected by `isLegacyRoadDamageOutputShape`. |
| `app/lib/services/tflite_agent_runner.dart` | Calls the two functions. Comments now say the D-codes are not proven equal to Crack/Pothole/Rutting/Uneven-Surface, and that thresholds are not the yaml table and not the settings slider. Removed the unused private `_thresholdFor` after the move. |
| `app/test/unit/legacy_stretch_contract_test.dart` | New. Locks stretch vs gray-114 letterbox. **Not executed** (no Flutter). |
| `app/test/unit/legacy_decoder_test.dart` | New. Locks top-left conversion, D40 cutoff 0.40, non-positive scores, `onlyD40`, and the shape gate. **Not executed** (no Flutter). |
| `test_images.py`, `test_single_image.py` | Comment only. Display strings unchanged. |

## Not changed on purpose

- No `.tflite` / `.pt` bytes.
- No image deletes or moves.
- No letterbox swap on the default model.
- No class rename in the Flutter UI.
- No settings-slider wiring.
- No dashboard metric JSON edit.
- No Supabase or SQL change.
- iOS ignored.

## Commands after the edits

| Command | Result |
|---|---|
| `python3 training/tests/test_contracts.py` | 2 passed (also 2 passed before the edits) |
| `npm test` in `dashboard` | 80 passed (also 80 before) |
| `python3 evaluation/android_model_audit/scripts/lock_android_contract.py` | CONTRACT OK |
| `python3 evaluation/android_model_audit/scripts/spec_decoder_math.py` | SPEC MATH OK |
| `validate_yolo_dataset.py` on the sparse image dir | BLOCKED, 0 labels, exit 2 |
| `plan_eval_manifest.py` on 29,120 git names | wrote `eval_plan_200.json` (138/29/33) |
| `flutter test` | BLOCKED, `flutter` missing |
| `adb devices` | BLOCKED, `adb` missing |

`git diff --stat` on tracked files:

```
 app/lib/inference/preprocessing.dart      | 13 +++++
 app/lib/services/tflite_agent_runner.dart | 93 ++++++++++++-------------------
 test_images.py                            |  6 ++
 test_single_image.py                      |  3 +
 4 files changed, 59 insertions(+), 56 deletions(-)
```

Untracked: `legacy_decoder.dart`, the two new unit tests, and `evaluation/`.
