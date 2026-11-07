# Prioritized action plan

Complexity is technical, not a calendar estimate. “Before a jury” means only a change that does not pretend to be a new model.

## P0

| | |
|---|---|
| Issue | Dashboard and `docs/dataset-audit.md` state mAP and class counts this repo cannot reproduce. |
| File | `dashboard/src/data/validation_metrics.json`, `docs/dataset-audit.md`, `training/reports/global_potholes_audit.json` |
| Current | UI can show D20 mAP50 0.964 and D40 mAP50 0.0001. Markdown claims 12,055 D40 boxes. |
| Expected | Those figures absent, or labeled not measured, until `validate_yolo_dataset.py` is VERIFIED and a test log exists. |
| Root cause | Numbers were committed without the split, the `.pt`, or the label files. |
| Fix | Do not quote them. A later edit can hide the JSON in the dashboard. This audit did not change the dashboard. |
| Complexity | Small copy change. |
| Depends on | Nothing to stop the claim. Labels and weights to replace it with a real number. |

## P0

| | |
|---|---|
| Issue | Default model has no ground truth. |
| File | `Global_Potholes_Dataset-image/` |
| Current | 29,120 jpeg, 0 labels. Audit JSON says STOP. |
| Expected | A labels directory that the validator accepts, then one test report. |
| Root cause | Images were committed unlabeled. |
| Fix | Annotate outside the image files. Use `eval_plan_200.json` only as a name list. |
| Complexity | Large for 29k images. The 200-name plan is the smaller protocol, and it is still not a result. |
| Depends on | Human labels. Not on a retrain. Do not retrain on empty labels. |

## P1

| | |
|---|---|
| Issue | Class gloss in `test_images.py` is not the app contract. |
| File | `test_images.py`, `test_single_image.py`, `app/lib/services/tflite_agent_runner.dart` |
| Current | Script: Crack, Pothole, Rutting, Uneven-Surface. App: D00, D10, D20, D40. |
| Expected | One proven map. Until then, both stay, with the script marked unproven. |
| Root cause | No names tensor and no labeled export. |
| Fix | Comments added. Labels not swapped. |
| Complexity | Done for the warning. A true map needs the training config that actually produced the TFLite. |
| Depends on | Weights metadata or the annotation guide used at training. |

## P1

| | |
|---|---|
| Issue | Legacy preprocess is stretch; Ultralytics training letterboxes. |
| File | `app/lib/inference/preprocessing.dart`, `tflite_agent_runner.dart` |
| Current | Stretch locked and called. One measured image moved a D20 box when letterboxed. |
| Expected | The preprocess that matches the missing export. |
| Root cause | `.pt` and export log are not in git. |
| Fix | Not applied. Switching now would be a guess. |
| Complexity | Medium once the `.pt` exists (compare 20 images, then change one path). |
| Depends on | Original weights. Not on a device. |

## P1

| | |
|---|---|
| Issue | Settings confidence slider does not affect inference. |
| File | `app/lib/screens/settings_screen.dart` (write), `tflite_agent_runner.dart` (no read) |
| Current | Prefs key `confidence_threshold` is unused by the runner. |
| Expected | Either the control is removed, or it is documented in the UI as not applied. Wiring it to a single threshold would change uncalibrated per-class cutoffs. |
| Root cause | UI and runner were written separately. |
| Fix | Not wired. Documented. |
| Complexity | Small. |
| Depends on | A val set if the slider is ever made real. |

## P1

| | |
|---|---|
| Issue | EXIF orientation is applied for display and for stored size, not for legacy inference. |
| File | `camera_detection_screen.dart`, `tflite_agent_runner.dart`, `annotated_image.dart` |
| Current | Three different decode paths. |
| Expected | One orientation before boxes are drawn. |
| Root cause | Runner uses `decodeImage`; the widget uses Flutter’s EXIF-aware loader. |
| Fix | Not changed (no device photo, and it alters pixels before the unproven stretch). |
| Complexity | Small once a rotated JPEG fixture exists. |
| Depends on | A device capture or a fixture with orientation 6. |

## P2

| | |
|---|---|
| Issue | Android speed is unknown. |
| File | n/a |
| Current | Linux invoke ~104–112 ms. |
| Expected | A phone trace: asset copy, first invoke, steady invoke, NNAPI on and off. |
| Root cause | No SDK, no adb, no device here. |
| Fix | Run on hardware. Do not install an SDK only to invent a number. |
| Complexity | Small on a machine that already has Flutter and a phone. |
| Depends on | Device. |

## P2

| | |
|---|---|
| Issue | No license. About 1.2 GB of unlabeled images are in git. Release is signed with the debug key. |
| File | repo root, `app/android/app/build.gradle.kts` |
| Current | LICENSE 404. `signingConfig = debug`. |
| Expected | A license that matches the data, images not required for the app clone, a release keystore outside git. |
| Root cause | Project packaging. |
| Fix | Not done. History rewrite is out of scope. |
| Complexity | Medium. |
| Depends on | Authors. Not on labels. |

## P3

| | |
|---|---|
| Issue | RoadSense is a second architecture sitting next to the default model. |
| File | `roadsense_agent_runner.dart` |
| Current | Off. NCHW, 9 channels, letterbox, drops its own D40 channel. |
| Expected | Stay off until a labeled run compares it with the legacy file. |
| Root cause | Two exports, one flag. |
| Fix | None. The legacy shape gate now refuses the 9-channel output if it were passed to the legacy runner. |
| Complexity | Already isolated by the flag. |
| Depends on | Labels if anyone wants to turn it on. |

## P3

| | |
|---|---|
| Issue | `namespace` is `com.example.tariqmap` while `applicationId` is `com.tariqmap.app`. |
| File | `build.gradle.kts`, `MainActivity.kt` |
| Current | Builds can still work; the Kotlin package matches the namespace. |
| Expected | A deliberate id before a store upload. |
| Root cause | Template leftover. |
| Fix | Not changed (can break the Gradle package path). |
| Complexity | Small, but not a model fix. |
| Depends on | Nothing scientific. |
