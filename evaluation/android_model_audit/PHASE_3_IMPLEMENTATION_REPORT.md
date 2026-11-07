# Phase 3 implementation report

Work is on the local clone at `/tmp/Road-damage-project`. HEAD is still `cd7d168` (`Fix Leaflet map layout and rendering`). Nothing was committed or pushed. Weights, datasets, `ios/`, production Supabase data and policies, and the 640×640 stretch path were not changed. Class codes stay D00, D10, D20, and D40. No mAP was computed or displayed. Phase 1 and Phase 2 uncommitted work is still in the tree.

Backups of the files this phase started from were copied to `evaluation/android_model_audit/backups/phase3/` before the edits. The new SQL file was not executed.

## P0 — Consistent ids for `submit_observation`

- Problem: A retry could treat an existing observation or receipt as finished and skip missing children, and the SQL function minted a new random id when an agent-run or detection id was absent.
- Root cause: `public.submit_observation` in `supabase/migrations/20261016_atomic_ingest_and_validation.sql` returns `already_synced` as soon as a receipt or the observation exists, and it uses `COALESCE(id, gen_random_uuid())` for agent runs and detections. The Flutter direct-insert path also wrote the receipt before the children when the RPC failed.
- Files: `supabase/migrations/20261105_submit_observation_stable_ids.sql` (new, not applied), `app/lib/data/remote/api_client.dart`, `app/lib/services/sync_plan.dart` (Phase 2, still used), `evaluation/android_model_audit/scripts/test_sql_id_contract.py`.
- Implementation: The replacement function keeps the same argument list. The client observation id is stored as `observations.id`. A missing agent-run or detection id raises. Inserts happen only when that id, or that location's `observation_id`, is absent. Old random-id rows are not deleted. The receipt is inserted only after the observation, the location, and every payload child id exist. Status is `synced`, `repaired`, or `already_synced`, and `success` stays true. Flutter still sends UUID v5 ids from the local observation id (`{id}:agent:{i}:{agent}`, `{id}:det:{i}:{j}`, media `{id}:original`). After the RPC or the direct observation insert, it selects existing child ids and inserts only the missing ones. `_ensureReceipt` runs after those children. A missing local image sets media to failed and throws, so the coordinator does not mark the row synced. Location identity stays `observation_id`. No new column was added.
- Expected improvement: A retry reuses the same ids, fills only missing children, and does not record a receipt for an incomplete payload.
- Tests: Local SQL comment-strip plus an in-memory `plan_submit`. No database was contacted.
- Results: 3 SQL-contract tests passed.
- Remaining risks: Production still runs the old function until this file is applied. A client that omits child ids will now fail closed instead of receiving a random id. Unknown class codes still fail the existing D00/D10/D20/D40 check and stay local. A unique index on locations was not added, because existing duplicate locations could make the migration fail.
- Deployment: Review the file on a staging database, confirm old random children are left in place, then apply it with the project's normal migration path. Do not run it against production from this clone. Do not auto-delete old rows.
- Status: PARTIALLY VERIFIED. The file and the client repair path match the contract tests. PostgreSQL was not executed.

## P0 — Legacy duplicate diagnostic

- Problem: Retries that used random child ids may have left duplicate observations, agent runs, or detections. Those rows must be classified before anyone deletes them.
- Root cause: The old function generated a new id whenever the payload omitted one, and the early `already_synced` return did not repair the first partial write.
- Files: `evaluation/android_model_audit/scripts/duplicate_diagnostic.py`, `evaluation/android_model_audit/scripts/test_duplicate_diagnostic.py`.
- Implementation: `classify_duplicates` is read-only. Confirmed means the same id appears more than once. Possible means different ids that share a capture id, or the same place within about 1e-5 degrees and 120 seconds and the same anomaly type, or the same observation and agent with different run ids, or the same observation, class, and box with different detection ids. The report always sets `deleted` and `merged` to 0. It does not connect to Supabase.
- Tests: Synthetic confirmed copies, possible distinct ids, and distinct classes that must not match.
- Results: 3 tests passed. A 1,500-row spaced sample finished in 0.077 seconds with 0 confirmed and 0 possible. That sample is not production data.
- Remaining risks: Place-and-time matches can flag two real nearby defects. The diagnostic was not run on production.
- Deployment: None. Do not point it at production until a human asks for a read-only export and reviews the report.
- Status: VERIFIED for the synthetic classifier. NOT VERIFIED against production rows.

## P0 — Flutter and Android validation

- Problem: Phase 2 Dart tests had not been executed because Flutter was absent.
- Root cause: The clone environment had Java and no Flutter, Dart, Android SDK, adb, or emulator.
- Files: No `pubspec.yaml` change. `flutter pub get` updated `app/pubspec.lock` (six transitive packages and the lock's recorded Dart lower bound). Edited Dart files were formatted. `preprocessing.dart` needed one more format pass after the first check.
- Implementation: Flutter 3.47.9 stable (Dart 3.13.7) was unpacked to `$HOME/sdk/flutter` from the official stable Linux tarball. That SDK satisfies `sdk: '>=3.4.0 <4.0.0'`. No root install. No dependency constraint in `pubspec.yaml` was edited.
- Tests: `flutter pub get`, `dart format --output=none --set-exit-if-changed` on the nine edited Dart files, `flutter analyze`, `flutter test`.
- Results: Pub get succeeded. Format of those nine files is clean. `flutter analyze` reports 33 info issues and no errors or warnings, and exits 1 because Flutter treats info as fatal. The infos are pre-existing (`prefer_const`, unnecessary imports, local underscores) plus `settings_screen.dart:220`, a one-line `if` that was already there. They were not mass-edited. `flutter test`: 134 passed, 13 failed. The 13 failures are missing image and golden fixtures (`Czech_000010.jpg`, `Japan_000008.jpg`, `China_Drone_000085.jpg`, RoadSense goldens, and the dashboard-map local image). They were not weakened and no images were invented. Phase 3 unit tests for class codes, confidence text, EXIF, sync plan, legacy decoder, stretch, and sync state passed inside that run. Debug APK was not built.
- Remaining risks: The lockfile now records Dart `>=3.11.0-0` and newer transitive versions of `characters`, `matcher`, `material_color_utilities`, `meta`, `test_api`, and `vector_math`. A checkout that uses an older Flutter still allowed by `pubspec.yaml` may not accept this lock. Direct dependency versions were not changed.
- Deployment: None from this machine. An APK still needs an Android SDK.
- Status: PARTIALLY VERIFIED for the Dart tests that ran. APK and device tests are BLOCKED. There is no Android SDK, `adb`, or emulator. Java 21 is present.

## P1 — Real EXIF

- Problem: Preview and inference could disagree with the phone's stored orientation, and an upright JPEG could be re-encoded.
- Root cause: The runner and the upload path did not share one orientation read, and invalid tags were not rejected before bake.
- Files: `app/lib/inference/preprocessing.dart`, `app/test/unit/exif_orientation_test.dart`. Pillow coverage stays in `evaluation/android_model_audit/scripts/test_exif_orientations.py`.
- Implementation: `readExifOrientation` returns null for a missing tag or a value outside 1–8. Orientation 1 and a null tag return the same image and the same upload bytes. Orientations 3, 6, and 8 are baked once. A second orient of an already baked image does not rotate again because bake clears the tag. Preview and inference both use `orientDecodedImage`. Stretch stays `copyResize` to 640×640. Rotated uploads are JPEG quality 95 once, then the existing compressor.
- Tests: Dart cases for orientations 1, 3, 6, and 8, missing EXIF, orientation 99, a 4×8 portrait, an 8×4 landscape, bake-once size, and stretch still 640. Pillow remains a supplement.
- Results: The Dart EXIF file passed inside `flutter test` (4 tests). Pillow: 6 passed. `lock_android_contract.py` still accepts the stretch call.
- Remaining risks: No camera capture on a device was checked. Pillow is not `package:image`.
- Status: VERIFIED for the Dart unit tests that ran. Device capture is NOT VERIFIED.

## P1 — Confidence slider UX

- Problem: The settings screen and the detector could describe different thresholds, and a moved slider could be confused with the saved value.
- Root cause: The runner had its own class-floor literals, and the screen did not say whether the active map was class-specific or one saved global score.
- Files: `app/lib/inference/confidence_threshold.dart`, `app/lib/services/tflite_agent_runner.dart`, `app/lib/screens/settings_screen.dart`, `app/test/unit/confidence_threshold_test.dart`.
- Implementation: Range stays 0.10–0.80. Until save, or when the stored value is null, NaN, or infinite, class floors stay: D00/D10 0.35, D20 0.30, D40 0.40. After save, the clamped score replaces every class on the next capture. The runner calls `activeThresholds`. The settings description uses `describeActiveThresholds` of the saved state, and adds `Slider preview is not applied until Save.` while the draft differs. NMS IoU stays 0.45 and is not the slider. The class-floor literals `'D40': 0.40` and `'D20': 0.30` remain in the runner so the stretch contract still matches.
- Tests: The displayed sentence for an unsaved 0.55 keeps D40 at 0.40 and D20 at 0.30 and says class-specific. A saved 0.55 is global, names 55%, and names NMS 45%.
- Results: Those Dart tests passed. The settings widget was not pumped.
- Remaining risks: Persistence across a process kill was not observed on a device. The shared function is what both the screen and the runner call.
- Status: VERIFIED for the shared function and the runner call. The settings widget itself is NOT VERIFIED in a widget test.

## P1 — Offline-first recovery

- Problem: A failed upload could retry without a stop, a missing image could still be marked synced, and a kill during `uploading` could leave a row stuck.
- Root cause: The attempt cap applied only while status was `pending`. The receipt could be written before children. Media failure did not always block the synced status.
- Files: `app/lib/services/observation_repository.dart`, `app/lib/data/remote/api_client.dart`, `backend/test_offline_recovery.py`.
- Implementation: Pending and failed rows both become `needsReview` when `uploadAttempts >= maxRetries` (default 5). The local row is kept. Backoff stays `min(2 * 2^attempt, 300)` plus the existing jitter. Startup still returns stuck `uploading` rows to `pending`. The client reuses UUID v5 ids, inserts only missing children, writes the receipt after them, and refuses to finish when the local image is missing or the media upload fails. A second sync does not copy children that already exist. No production storage call was added.
- Tests: In-memory `Remote` and `LocalRow` cover offline capture, later reconnect, auth expiry, failed media, failed observation insert, failed child insert, kill during sync, restart with pending, the attempt cap, and a duplicate sync request. Dart `sync_state_test.dart` covers stuck upload, failed increment, needsReview, cancel, and completion.
- Results: 7 Python tests passed. The Dart sync-state tests passed inside `flutter test`.
- Remaining risks: The Python simulator is not the Flutter client. Media recovery uses the existing storage upload in `api_client.dart`; it was not executed against a bucket. Auth expiry is simulated, not a live JWT.
- Status: VERIFIED for the mock and the Dart coordinator tests. Live storage is NOT VERIFIED.

## P1 — Supabase client configuration

- Problem: A production dashboard bundle could contain the public anon key fallback, and a release Flutter build could do the same when dart-defines were empty.
- Root cause: Both clients used the literal whenever the env var was empty, including production builds.
- Files: `dashboard/src/supabase.js`, `dashboard/src/supabaseConfig.test.js`, `app/lib/core/supabase_config.dart`, `supabase/recommended/rls_and_storage_NOT_APPLIED.sql`. Example placeholders from Phase 2 stay in `dashboard/.env.example`, `backend/.env.example`, and `app/dart_defines.example.json`.
- Implementation: Vite uses the debug anon literal only when `import.meta.env.DEV` is true, so the production build dead-code-eliminates it. Flutter uses the literal only when `kDebugMode` is true. A release build without `--dart-define` gets an empty URL and key and `assertPublicConfig` fails without printing the key. A JWT whose payload role is `service_role` is still refused. The recommended RLS and storage text is comments in `supabase/recommended/`, not a migration, and it was not applied. Env vars do not replace RLS.
- Tests: Dashboard config tests. Production bundle search after `vite build`.
- Results: Vitest includes the config tests (93 passed overall). The built JS does not contain the project ref `lendqcjihusqkmxansbl` or an `eyJ` token. It does contain the word `service_role` because the startup check compares the role name. That is not a service-role secret.
- Remaining risks: Debug and `flutter run` still contain the public anon literal. RLS was not changed. A public anon key is still a public key; policies are what limit it.
- Deployment: Do not apply `rls_and_storage_NOT_APPLIED.sql` until staging has an authenticated insert path. Applying the commented policies as written would stop the current anon ingest.
- Status: PARTIALLY VERIFIED. The production bundle check passed. Policies were not executed.

## P1 — Dashboard and backend consistency

- Problem: Repeated ids could be counted twice, a missing timestamp could be treated as now, unknown classes could be shown as D40, and the observation list stopped at 500 with no way to continue.
- Root cause: Analytics used the raw list and `Date.now()` when a date was missing. `fetchObservations` returned a single page and dropped the truncation flag. Ministry display used the raw class.
- Files: `dashboard/src/utils/records.js`, `dashboard/src/utils/records.test.js`, `dashboard/src/utils/commandCenterAnalytics.js`, `dashboard/src/utils/ministryAnalytics.js`, `dashboard/src/supabase.js`, `dashboard/src/App.jsx`. Backend validation from Phase 2 stays in `backend/main.py`, `backend/schemas.py`, and `backend/supabase_store.py`.
- Implementation: `uniqueObservations`, `eventTimeMs`, `utcDayKey`, and `mergeObservationPages` are the shared helpers. A missing or invalid time is null and is left out of dated windows. Day keys are UTC dates. Unknown display uses `displayClassCode`, so it stays `Unknown class` and is not D40. Empty rates stay empty. No accuracy number was added. `fetchObservations` returns `{ rows, truncated }` with a page cap of 500. The dashboard shows a truncation banner and loads older rows with `created_at` less than the oldest loaded time, merged by id.
- Tests: `records.test.js` plus the existing analytics tests. Backend API validation tests.
- Results: Vitest 19 files, 93 tests passed. `vite build` succeeded. Backend API validation: 6 passed. The Load older button was not clicked in a browser.
- Remaining risks: Truncation is based on the query page before the latitude/longitude filter, so a page of rows that are all filtered out can still say truncated. Timezone display elsewhere in the app was not audited line by line.
- Status: VERIFIED for the functions under test. The dashboard page was not exercised in a browser, so the banner click is NOT VERIFIED.

## P2 — UX

- Problem: The slider did not say which threshold was active, a full observation list looked complete, and a permanently failing sync looked like an endless retry.
- Root cause: The screen described the draft, the list had no truncation state, and failed rows were not moved to review.
- Files: `settings_screen.dart`, `App.jsx`, `offline_queue_screen.dart` and `home_screen.dart` (existing needs-review labels, now reachable from the cap).
- Implementation: The settings text names class-specific floors or the saved global score, and it says the preview is not applied until Save. The dashboard banner is a status region with Load older / Charger les plus anciens. Needs-review stays the existing error color and label. No visual redesign. Camera error and retry screens from Phase 2 were left in place.
- Tests: Confidence text tests. No widget test of the settings screen. No browser pass. No emulator.
- Results: The sentence tests passed. Layout on a phone and in a browser was not checked.
- Status: PARTIALLY VERIFIED.

## What was not done

Letterbox was not introduced. Classes were not renamed. No weights or datasets were edited. No mAP was invented. No observation was deleted. No production SQL was executed. `ios/` was not edited. The model is still not scientifically validated. `validation_metrics.json` is still unused by the UI.
