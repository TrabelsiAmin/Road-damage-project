# Phase 2 implementation report

Work is on the local clone at `/tmp/Road-damage-project`. Nothing was committed or pushed. Weights, datasets, `ios/`, production Supabase, and the 640×640 stretch path were not changed. Class codes stay D00, D10, D20, and D40. No mAP was computed or displayed.

Phase 1 behavior is still in place: stretch lock, legacy decoder shape gate, dashboard metrics shown as not available, API validation redaction, UUID v5 child ids, and the earlier error/retry screens.

Backups of the files this phase edited were copied to `evaluation/android_model_audit/backups/phase2/` before the edits.

## P0 — Missing class

- Problem: Several screens and analytics paths treated a missing class as D40, which both mislabels the row and inflates D40 counts.
- Root cause: Display and filter code used `|| 'D40'` (and the Dart equivalent `?? 'D40'`) when `anomaly_type` or `class_code` was absent.
- Files: `dashboard/src/utils/classCodes.js`, `app/lib/core/class_codes.dart`, and the call sites in the dashboard analytics/components plus `dashboard_map.dart`, `upcoming_anomaly.dart`, `result_screen.dart`, `annotated_image.dart`, `frame_annotator.dart`, and `annotation_renderer.dart`.
- Implementation: One handler on each side. Known codes stay D00/D10/D20/D40. Anything else displays `Unknown class`. `statClassCode` returns null, so the row is left out of those four buckets. Stored rows are not rewritten. Existing plain-language strings for the four known codes are unchanged, and the result card still says that wording is unconfirmed. No new human-readable names were added.
- Expected improvement: A null or D99 observation no longer appears as a pothole in filters, budgets, clusters, exports, or the map card.
- Tests: `classCodes.test.js`, `analyticsConsistency.test.js`, and the existing command-center tests. Dart tests are in `app/test/unit/class_codes_test.dart`.
- Results: Dashboard tests passed. Dart tests were not executed.
- Limitations: `dashboard/src/utils/ministryAnalytics.test.js` still builds a fixture with `anomaly_type || 'D40'`. That is test data, not the production path. `Detection.classLabel` still returns the raw code for an unknown value because `coordinate_test.dart` expects `D99`. The visible label uses `Unknown class`.
- Status: PARTIALLY VERIFIED. Dashboard behavior is verified. The Flutter handler is BLOCKED until Dart runs.

## P0 — Partial offline sync

- Problem: A retry treated an existing observation row, or an existing receipt, as a finished sync and skipped missing agent runs and detections.
- Root cause: `insert_observation` returned `already_received` as soon as the observation or receipt existed. The Flutter RPC conflict path did the same and did not insert the missing children.
- Files: `backend/supabase_store.py`, `app/lib/data/remote/api_client.dart`, `app/lib/services/sync_plan.dart`, `app/lib/services/observation_repository.dart`.
- Implementation: Child ids stay UUID v5 from the local observation id (`{id}:agent:{index}:{agent}` and `{id}:det:{index}:{detIndex}`). A retry inserts only ids that are absent. A receipt is written only after the observation, location, agent runs, and detections for that payload are present. Status is `created`, `repaired`, or `already_received`. HTTP remains 201 with `{status, id}`. The observation stays pending until observation, children, media, auth, and network all succeed. Local rows are not deleted. Stuck `uploading` rows return to `pending` on startup. Sync errors are redacted before they are stored.
- Expected improvement: An interrupted upload can be retried without a second copy of the children that already exist, and it is not marked synced while media or auth is still failing.
- Tests: `backend/test_sync_recovery.py` (in-memory `_request`, no HTTP). Dart: `app/test/unit/sync_plan_test.dart`.
- Results: 11 Python tests passed, including complete sync, partial repair, duplicate retry, network failure before the receipt, auth failure with no inserts, and the rule that an older random child id is left in place. Dart tests were not executed.
- Limitations: Media bytes are uploaded by the Flutter client, not by `insert_observation`. The Python media case checks that this method never posts `media_files` and that the completion rule stays false when media is false. It does not run the camera upload. Children written earlier with random ids are not deleted, so a stable-id insert can sit beside them. If the SQL function `submit_observation` ignores the client ids and inserts its own, the client may add a second semantic child. That function was not changed. No production Supabase call was made.
- Status: PARTIALLY VERIFIED. The store planner is verified in memory. The Flutter upload and restart path is BLOCKED.

## P1 — EXIF orientation

- Problem: Preview, YOLO input, and upload could disagree. Flutter’s image widget applies EXIF, while the runner stretched the raw decode, and the compressor stripped EXIF without baking pixels.
- Root cause: `decodeAndOrient` did not bake, and the runner decoded without orientation.
- Files: `app/lib/inference/preprocessing.dart`, `tflite_agent_runner.dart`, `annotation_renderer.dart`, `frame_annotator.dart`, `api_client.dart`.
- Implementation: Orientation is read once. Missing, malformed, or orientation 1 returns the same image and the same upload bytes, so an upright JPEG is not encoded again before the existing WebP step. Orientations 3, 6, and 8 are baked once. A bake failure keeps the decoded pixels. Rotated uploads are JPEG quality 95 once, then the existing compressor. Stretch is still `copyResize` to 640×640. Boxes are drawn on the oriented image.
- Expected improvement: A phone photo that is stored sideways is turned before the model and before upload, and an already-upright photo is not recompressed by this step.
- Tests: `evaluation/android_model_audit/scripts/test_exif_orientations.py` (Pillow geometry for orientations 1, 3, 6, 8, missing, and malformed, plus a source check that stretch is unchanged). Dart: `app/test/unit/exif_orientation_test.dart`.
- Results: 6 Python tests passed. Dart tests were not executed. `lock_android_contract.py` still accepts the stretch call.
- Limitations: The Python tests use Pillow’s EXIF transpose as the geometry oracle. They do not execute `package:image`’s `bakeOrientation`. A device capture was not checked.
- Status: PARTIALLY VERIFIED.

## P1 — Confidence slider

- Problem: Settings saved `confidence_threshold` and the detector ignored it.
- Root cause: The runner kept a fixed per-class map and never read SharedPreferences.
- Files: `app/lib/inference/confidence_threshold.dart`, `tflite_agent_runner.dart`, `settings_screen.dart`.
- Implementation: Range stays 0.10–0.80. Null, NaN, and infinity are rejected. Until the user saves, `confidence_threshold_set` is false and the class defaults stay (D00/D10 0.35, D20 0.30, D40 0.40). After a save, the clamped value replaces every class on the next capture without reloading the interpreter, and the D40 override is cleared. NMS IoU stays 0.45 and is not the slider. The settings text says which of those two states is active. Defaults were not chosen from test metrics.
- Expected improvement: A saved slider is the threshold the next capture uses, and the screen says so. An unsaved install keeps today’s class floors.
- Tests: `app/test/unit/confidence_threshold_test.dart`.
- Results: Not executed. `flutter` and `dart` are absent. A Python copy of the clamp was not used as a pass.
- Limitations: The wiring is in the runner, which cannot be imported here. Persistence across a real process restart was not observed.
- Status: BLOCKED.

## P1 — Supabase client config

- Problem: The public client needs a startup check that refuses a service-role key and still starts for the current local anon fallback.
- Root cause: The dashboard and Flutter app embed the public anon key. That key is not a service-role secret. Blanking it would stop local runs that have no env var.
- Files: `dashboard/src/supabase.js`, `app/lib/core/supabase_config.dart`, `app/lib/data/remote/supabase_service.dart`, `dashboard/.env.example`, `backend/.env.example`, `app/dart_defines.example.json`.
- Implementation: URL and anon key are read from Vite env or `--dart-define`, with the existing public anon literal as the fallback. Startup refuses an empty URL, an empty key, or a JWT whose payload role is `service_role`. The error does not include the key. Supabase debug logging on the Flutter client is off. Example files contain placeholders only. The service-role key remains an environment variable for the backend.
- Expected improvement: A service-role key cannot be used as the client key. Local runs that do not set env still start. The key is not written to logs by this check.
- Tests: `dashboard/src/supabaseConfig.test.js`.
- Results: The dashboard assertions passed. The Flutter `assertPublicConfig` was not executed.
- Limitations: The anon literal is still in source. RLS and Storage policies were not changed. See the security review.
- Status: PARTIALLY VERIFIED.

## P1 — Dashboard data consistency

- Problem: Empty sets could look complete, and a missing class could add a D40 cost or a D40 filter hit.
- Root cause: Budget used a 250 fallback, export used priority 50, and class filters used the D40 default.
- Files: `commandCenterAnalytics.js`, `clustering.js`, `exportFormats.js`, `roadSegmentRisk.js`, `ministryAnalytics.js`, `ActionCenterView.jsx`, `CaseDetailModal.jsx`, `RoadSegmentRiskView.jsx`.
- Implementation: Shared class helpers feed filters, quality counts, clusters, exports, segment counts, and the ministry summary. Empty quality percents stay null. An empty repair rate stays null rather than 0% or 100%. Unknown and missing classes add no catalogue cost. Export leaves a missing priority blank. `avgResolutionDays` stays null. The French metrics title is unchanged. No accuracy figure was invented.
- Expected improvement: Totals for the four class buckets plus unspecified detections match the detections that were stored. D99 does not increase D40.
- Tests: `analyticsConsistency.test.js` and the existing analytics tests.
- Results: Vitest 90/90, including the new empty and incomplete cases.
- Status: VERIFIED for the functions those tests call. The pages were not clicked in a browser.

## P2 — UX

- Problem: A signed-image failure in the case dialog looked like “no photo”.
- Root cause: The catch path cleared the loading flag and fell through to the empty state.
- Files: `dashboard/src/components/CaseDetailModal.jsx`. Phase 1 camera, startup, queue, and result error/retry screens were left in place.
- Implementation: A failed signed URL or a broken image shows an error and a retry button. A row with no media still shows the empty state. Class text on the result card and history card uses the shared handler.
- Expected improvement: The operator can tell a missing photo from a failed load and can retry the signed URL.
- Tests: esbuild of `App.jsx` succeeded. No browser pass.
- Limitations: The new dialog state was not clicked. Flutter screens were not run.
- Status: PARTIALLY VERIFIED.

## P2 — API reliability

- Problem: Store errors and validation echoes could leak tokens, and a short or out-of-range payload was not rejected.
- Root cause: Phase 1 already added validation and redaction. Phase 2 kept that path and stopped class stats from labeling a blank `class_code` as a class.
- Files: `backend/main.py` (unchanged this phase beyond the Phase 1 behavior already in the tree), `backend/supabase_store.py`, `backend/schemas.py`.
- Implementation: 422 details stay an array. Image and JWT-shaped inputs are `[redacted]`. Store failures return a generic 502 and a log line that does not include the payload. The HTTP client timeout stays 20s with a 5s connect. No new retry loop was added. The observation response is still `{status, id}`. `status` may now be `repaired` when only missing children were inserted. `by_class` omits a blank class instead of calling it D40 or UNKNOWN. A missing priority label is not counted as LOW.
- Expected improvement: A bad body cannot echo a token, and a class tally cannot invent D40.
- Tests: `backend/test_api_validation.py` (6) and the stats case inside `test_sync_recovery.py`.
- Results: Both passed. They do not call the hosted project.
- Status: VERIFIED for those tests.

## Final tree check

- Branch `main` at `cd7d168`. No commit and no push.
- Tracked diff: 38 files, +1217 / −462.
- `ios/` has no diff. No `.tflite`, `.pt`, or `.onnx` path is modified.
- `flutter` and `dart` are not installed.
