# Suggestions pending approval

These were not implemented. Each one can change a number, a label, a security policy, or a platform this pass was told to leave alone.

## 1. Switch stretch to letterbox

- Problem: Ultralytics training usually letterboxes. The Android runner stretches the frame to 640×640 with `stretchToModelInput`.
- Evidence: `road_damage.tflite` is NHWC `[1, 640, 640, 3]` → `[1, 8, 8400]`. On one 480×640 image (`b784e91c`), stretch kept a D20 at 0.629 with box height 0.197, and letterbox kept a D20 at 0.556 with box height 0.140, at a 0.25 floor. That is one unlabeled image, not mAP. The `.pt` export is not in the repo.
- Risk: Shipping letterbox without the matching weights would move every box and score. The stretch contract tests would have to change with it.
- Change if approved: letterbox only after the original `.pt` or an export log shows that this TFLite was exported with letterbox, then re-check boxes on a labeled set. Until then, keep stretch.

## 2. Rename D00 / D10 / D20 / D40

- Problem: `test_images.py` prints Crack, Pothole, Rutting, and Uneven-Surface for indexes 0–3. The app stores D00, D10, D20, and D40. The dashboard French names are a third wording.
- Evidence: The TFLite file embeds `YOLOv8_Small_RDD` and does not embed a names list. There are 0 label files. Nothing in this repo proves index 3 is “Uneven-Surface” or that D40 is “Pothole” in the RDD sense.
- Risk: Renaming the stored code would split history, sync payloads, and filters. Renaming only the plain-language string would still present an unproven name as fact.
- Change if approved: keep the stored code. Add a name only from model metadata or a labeled export that maps index to name. The result screen already says the current plain-language name is unconfirmed.

## 3. Retraining

- Problem: There is no completed training run in this repo that reproduces `road_damage.tflite`.
- Evidence: No `.pt` and no `.onnx` in the tree. `training/reports/global_potholes_audit.json` records the image set as unlabeled and says stop. `*.pt` is gitignored.
- Risk: Training on unlabeled images, or on labels invented to match a script’s class names, would produce a new model that cannot be compared with the one on device.
- Change if approved: do not train until a labeled YOLO set and a known class map exist. Do not replace the shipped `.tflite`.

## 4. Labeled evaluation set

- Problem: Accuracy cannot be computed.
- Evidence: `git ls-tree` has 29,120 jpgs under the dataset path and 0 label files. `docs/dataset-audit.md` class counts contradict the audit JSON and should not be quoted. `dashboard/src/data/validation_metrics.json` (D20 mAP50 0.964 and the other rows) has no eval log beside it. The dashboard no longer displays those rows.
- Risk: Building labels by hand, or treating the JSON as a measurement, would publish a fake accuracy.
- Change if approved: add a small human-labeled val set with the same class ids the app stores, run the current TFLite with stretch, and only then show precision, recall, and mAP. `evaluation/android_model_audit/scripts/plan_eval_manifest.py` only writes a plan. It does not label or move files.

## 5. Android device benchmark

- Problem: Latency and memory on a phone are unknown.
- Evidence: This machine has no `flutter`, no `adb`, and no emulator. Earlier figures (about 104 ms and about 112 ms mean invoke on Linux CPU, XNNPACK, 2 threads, n=12 and n=8) are not Android, not GPU, and not a frame-time budget. Process RSS after both interpreters was about 394 MB on that Linux host and was not per model.
- Risk: Quoting the Linux times as phone times would overstate readiness. Installing a full Android SDK here was out of scope.
- Change if approved: on a device, time `Interpreter.run` only, record the device model, delegates, thread count, and image size, and keep the interpreter created once. Do not compare that number with the Linux means without saying they are different machines.

## 6. Supabase RLS migrations

- Problem: The backend uses a service-role key from the environment, and the clients use the anon key. RLS was not reviewed or changed.
- Evidence: `backend/supabase_store.py` reads `TARIQMAP_SUPABASE_SERVICE_ROLE_KEY` or `SUPABASE_SERVICE_ROLE_KEY`. No service-role JWT is in the client tree. `training/test_rls.py` talks to the live project and was not run.
- Risk: A migration applied from this machine would change production. A wrong policy can lock out the app or open rows.
- Change if approved: review policies in a branch or a staging project, with a written allow-list for anon insert versus service-role insert. Do not run that SQL against production from this clone.

## 7. Move the hardcoded anon key to the environment

- Problem: The public anon key is a string literal in `app/lib/core/supabase_config.dart`, `dashboard/src/supabase.js`, and `training/seed_demo_data.py`.
- Evidence: The JWT payload’s role is `anon`. It is not a service-role key. The dashboard already prefers `VITE_SUPABASE_ANON_KEY` and falls back to the literal so a missing env still starts. The Flutter app has no such fallback path.
- Risk: Replacing the literal with an empty default bricks local runs that do not have the env var. Rotating the key in git history is a separate decision. The value was not printed in this report.
- Change if approved: keep the current literal as the fallback until a build injects the same anon key, then remove the literal from source and from git history if the project wants it gone. Do not put a service-role key in the client.

## 8. iOS

- Problem: The iOS project, Podfile, and signing were not checked or updated in this pass.
- Evidence: The task is Android-only. `ios/` was not edited.
- Risk: A Podfile or signing edit can break the iOS build and is unrelated to the TFLite stretch contract on Android.
- Change if approved: a separate pass that does not share the Android model-load change unless the same Dart files are intentionally shared and re-tested on an iOS device.

## Also left unchanged

- Settings slider (`confidence_threshold`) is written in `settings_screen.dart` and is not read by `TFLiteAgentRunner`. Wiring it would apply an uncalibrated global threshold on top of the per-class thresholds.
- EXIF orientation is baked for the stored width and height (`decodeAndOrient`) and is not baked inside the runner before stretch. Changing that changes pixels with no device fixture.
- Clustering, case detail, exports, segment risk, and the class filter still treat a missing class as `D40`. Data-quality counts no longer do. Changing the rest would move markers and budget figures for old rows that have no class.
- A partial sync that inserted the observation row and then failed before detections is detected as `already_received` and is not repaired. Fixing that needs a defined server rule, not a silent second insert.
