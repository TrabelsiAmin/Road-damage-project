# Implementation report

Scope: local clone `/tmp/Road-damage-project`. No commit, no push, no retrain, no weight or dataset overwrite, no production Supabase write, no remote schema change, no `ios/` edit.

The model is still not scientifically validated. Nothing in this change measures mAP, precision, or recall.

## What changed

### Flutter Android UI

- `app/lib/main.dart` — theme already used `AppColors` and Inter. Added a teal `progressIndicatorTheme` only.
- `app/lib/screens/result_screen.dart` — each detection shows the stored class id (`D00`, `D10`, `D20`, `D40`, or whatever was decoded) and the existing plain-language label with the note “plain-language name is unconfirmed”. Confidence and box values are unchanged. If an agent result has an error and there are no boxes, the screen says inference failed instead of “No road anomalies detected”.
- `app/lib/screens/camera_detection_screen.dart` — camera init failure or no camera shows an error and a Retry button. The analysing overlay and single-shot capture path are unchanged. The TFLite interpreter is still created once in `TFLiteAgentRunner`, not per frame. This screen was not reloading the model per frame, so that path was left as it was.
- `app/lib/screens/home_screen.dart` — startup failure shows an error and Retry instead of continuing into widgets that need the repository. Capture errors still use the existing banner. History still has the empty “No inspections yet” state. The sync button label is `Retry` when there are failed rows and no pending rows. It still calls the existing `SyncCoordinator.syncPending`, which already retries pending and failed rows. An unexpected sync throw is shown as “Sync failed.” without the exception text.
- `app/lib/screens/offline_queue_screen.dart` — load failure shows an error and Retry. Failed and needs-review cards have a Retry button that calls the same sync callback. Sync All is unchanged and still retries failed rows.

`ios/` was not opened for edits.

### Inference

- `app/lib/inference/preprocessing.dart` — `stretchToModelInput` remains the legacy path. Letterbox was not swapped in.
- `app/lib/inference/legacy_decoder.dart` — decoder for output `[1, 8, 8400]`. `isLegacyRoadDamageOutputShape` rejects `[1, 9, 8400]`.
- `app/lib/services/tflite_agent_runner.dart` — one interpreter per runner. Load fails with a clear error unless the input is NHWC `[1, 640, 640, 3]` and the output passes the legacy shape gate. RoadSense NCHW `[1, 3, 640, 640]` fails that input check. Class codes stay `D00`–`D40`. Thresholds stay D00/D10 0.35, D20 0.30, D40 0.40.
- `app/test/unit/legacy_decoder_test.dart` and `app/test/unit/legacy_stretch_contract_test.dart` — Dart contracts. Not executed (no Flutter/Dart binary).
- `evaluation/android_model_audit/scripts/spec_decoder_math.py` — Python mirror of the decoder numbers, the shape gate, stretch versus letterbox geometry for a 640×480 frame, class-aware NMS, and rejection of an NCHW input shape.
- `evaluation/android_model_audit/scripts/lock_android_contract.py` — still checks the stretch call and the shape gate in the runner.
- `test_images.py`, `test_single_image.py` — comments only. Display strings in those scripts were not renamed.

### Dashboard

- `dashboard/src/App.jsx` — the metrics modal title stays `Métriques IA & Limites`. The body is “Not available” with the reason that this repo has no labeled evaluation set. `validation_metrics.json` is no longer imported. The JSON file is still on disk and is not displayed. The values in it, including D20 mAP50 0.964, are not measurements from this repo.
- `dashboard/src/components/layout/Topbar.jsx` — the metrics button tooltip no longer says those figures are validation results.
- `dashboard/src/components/DataQualityView.jsx` — confidence bars use stored scores only, with the thresholds the analytics function actually uses (≥ 0.65 high, 45–65 medium, < 0.45 low). Empty confidence, GPS accuracy, or media counts show “Not available”. The “Bundle v2.1 RoadSense” badge is gone. Class chips keep the stored code and say the plain-language name is not confirmed. Feedback success text says the note stays in the session.
- `dashboard/src/utils/commandCenterAnalytics.js` — empty observations no longer return high confidence 100. A detection with no `class_code` increments `unspecifiedClassCount` and does not increment D40. Confidence `0` stays low; a missing confidence is not replaced with 0.5. GPS percent is the share of stored `accuracy_meters` above 25 m. Media percent is the share of rows with a stored media path. Missing class no longer uses the D40 repair cost in the budget totals in this file. `avgResolutionDays` was the constant 14.5 and was not shown; it is now `null`.
- `dashboard/src/index.css` — unavailable-state style and a single-column quality grid under 768 px.
- `dashboard/src/utils/commandCenterAnalytics.test.js` — existing mock expectations kept, plus an empty-input and missing-class case.
- `dashboard/src/utils/metricsHonesty.test.js` — source check that `App.jsx` does not render `row.map50`, `0.964`, or `validation_metrics.json`.

Maps, filters, observation lists, and media loading were not rewritten. Other screens still fall back to `D40` when a class is missing (clustering, case detail, exports, segment risk, the class filter). That was left in place because those paths feed existing lists and tests.

### FastAPI

- `backend/schemas.py` — length and range checks on ids, class code, agent name, actor, accuracy, and image dimensions. Class code is not restricted to D00–D40, so an unknown stored code still validates. Response models are unchanged.
- `backend/main.py` — list `limit` is 1–500. Store failures return a fixed 502 detail, `The observation store rejected the request`, and the log line does not include the exception text. Detect failures return `Inference failed` and do not log the exception text. Validation errors still use HTTP 422 and a `detail` array. `image_b64`, JWT-shaped strings, and inputs longer than 256 characters are replaced with `[redacted]` in that array.
- `backend/supabase_store.py` — `redact_secrets` strips JWT-shaped tokens from store error text before it is put in a `RuntimeError`. `insert_observation` returns `already_received` when a sync receipt or the observation row already exists. Agent-run and detection ids are UUID v5 from the observation id and indexes. If the observation row exists but child rows were never written, this does not fill them in.
- `backend/test_api_validation.py` — six tests. They use FastAPI `TestClient` against invalid bodies and a stubbed store error. They do not call `/v1/health` or a live project.

### Supabase client

- No service-role key was found in the Flutter or dashboard client. None was printed. The hardcoded anon key was not removed and was not replaced with an empty environment variable.
- `app/lib/core/supabase_config.dart` and `dashboard/src/supabase.js` — comments only: the embedded value is the public anon key local runs already use, and a service-role key does not belong in the client or in logs.
- `app/lib/data/remote/api_client.dart` — agent-run and detection ids are UUID v5 from the local observation id and indexes. A retry of the same observation therefore hits the existing unique-conflict success path instead of inserting a second set of child rows. Media ids were already stable.

## Tests actually run

| Check | Result |
| --- | --- |
| `python3 training/tests/test_contracts.py` | 2 passed |
| `python3 evaluation/android_model_audit/scripts/lock_android_contract.py` | `CONTRACT OK` |
| `python3 evaluation/android_model_audit/scripts/spec_decoder_math.py` | `SPEC MATH OK` |
| `python3 backend/test_api_validation.py` | 6 passed |
| `npm test` in `dashboard/` (vitest run) | 15 files, 83 passed |

The previous dashboard run was 80 passed. The three new tests are the empty/missing-class analytics case and the two source checks in `metricsHonesty.test.js`.

`flutter` and `dart` are not on `PATH`. `app/test/unit/legacy_decoder_test.dart` and `app/test/unit/legacy_stretch_contract_test.dart` were not executed. That is not a pass.

Not run, on purpose: `test_rls.py`, `test_supabase.py`, `test_sync_simulation.py`, anything that would call the hosted Supabase project, training, and any Android device or emulator. `adb` is not available. No mAP was computed. The 29,120-image git tree still has 0 label files in this checkout.

`fastapi`, `httpx`, `pydantic`, and `python-dotenv` were installed into the user site only so the new API tests could import. They were not added to the app and no production credential was printed.

## Files touched

Modified tracked files (`git diff --stat` at the time of this report):

- `app/lib/core/supabase_config.dart`
- `app/lib/data/remote/api_client.dart`
- `app/lib/inference/preprocessing.dart`
- `app/lib/main.dart`
- `app/lib/screens/camera_detection_screen.dart`
- `app/lib/screens/home_screen.dart`
- `app/lib/screens/offline_queue_screen.dart`
- `app/lib/screens/result_screen.dart`
- `app/lib/services/tflite_agent_runner.dart`
- `backend/main.py`
- `backend/schemas.py`
- `backend/supabase_store.py`
- `dashboard/src/App.jsx`
- `dashboard/src/components/DataQualityView.jsx`
- `dashboard/src/components/layout/Topbar.jsx`
- `dashboard/src/index.css`
- `dashboard/src/supabase.js`
- `dashboard/src/utils/commandCenterAnalytics.js`
- `dashboard/src/utils/commandCenterAnalytics.test.js`
- `test_images.py`
- `test_single_image.py`

New untracked code and tests:

- `app/lib/inference/legacy_decoder.dart`
- `app/test/unit/legacy_decoder_test.dart`
- `app/test/unit/legacy_stretch_contract_test.dart`
- `backend/test_api_validation.py`
- `dashboard/src/utils/metricsHonesty.test.js`
- `evaluation/android_model_audit/scripts/spec_decoder_math.py` (extended)
- `evaluation/android_model_audit/scripts/lock_android_contract.py` (from the prior audit, kept)

Copies made before the later edits are under `evaluation/android_model_audit/backups/`. The prior audit write-ups in `evaluation/android_model_audit/` were not rewritten by this pass except this file, `SUGGESTIONS_PENDING_APPROVAL.md`, and the decoder-math script.

## Limitations

- No labeled eval set, so no accuracy number is claimed.
- Stretch versus letterbox was measured earlier on one image only. That is not a reason to switch preprocess. Stretch stays.
- Flutter widget and unit tests were not run.
- Android latency was not measured. Earlier Linux CPU timings are not phone timings.
- Idempotent child ids stop a second insert of the same local observation. They do not repair a partial write where the observation row exists and the detections do not.
- The public anon key is still hardcoded so local runs keep working.
- Several dashboard views still display a missing class as `D40`.
- The Settings confidence slider is still not read by the runner.
- Camera bytes are still decoded without an EXIF bake before stretch. Changing that would change pixels without a device fixture.
- `validation_metrics.json` remains in the tree. It is unused by the UI.
