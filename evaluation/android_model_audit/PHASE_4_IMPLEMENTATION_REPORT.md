# Phase 4 implementation report

Work is on `/tmp/Road-damage-project`. HEAD is still `cd7d168`. Nothing was committed or pushed. Weights, datasets, `ios/`, production Supabase, and the 640×640 stretch path were not changed. Class codes stay D00, D10, D20, and D40. No mAP was invented. No observation was deleted. Phase 1–3 files are still in the tree.

Backups of files this phase edited are under `evaluation/android_model_audit/backups/phase4/`.

## P0 — The 13 Flutter failures

Each failure was inspected before any source edit. All 13 stopped on a missing file under `app/test/goldens/images/`. Those JPEGs are tracked at HEAD. They were absent because sparse checkout excludes `app/test/goldens/images/**` and the index marks them skip-worktree. `git cat-file` showed real JPEG blobs (Czech and Japan 600×600, China Drone 512×512, Norway also present). They are not placeholders.

| Test | Missing fixture | Where it lives | Verdict |
| --- | --- | --- | --- |
| Detection pipeline: known crack image through SQLite | `Czech_000010.jpg` and its tensor bin (the bin was already on disk) | HEAD blob `75ccf19` | Fixture, not a logic bug |
| Detection pipeline: null dimensions | `Czech_000010.jpg` | same blob | Fixture |
| Thumbnail: skip when there is no detection | `Czech_000010.jpg` | same blob | Fixture |
| Thumbnail: 25% margin crop under 250 KB | `Czech_000010.jpg` | same blob | Fixture |
| Thumbnail: minimum crop and 2.5:1 aspect | `Czech_000010.jpg` | same blob | Fixture |
| Thumbnail: box area below 0.5% | `Czech_000010.jpg` | same blob | Fixture |
| RoadSense letterbox geometry across 5 images | the five golden JPEGs | HEAD blobs | Fixture. This test exercises `letterboxProcess`, which is the RoadSense path. Stretch was not changed to make it pass |
| RoadSense `imageToNchwFloat32` | the same five JPEGs | HEAD blobs | Fixture |
| Real photo thumbnail: Czech_000010 | image plus `tensors/Czech_000010_output.bin` | image was missing; tensor was present | Fixture |
| Real photo thumbnail: Japan_000008 | `Japan_000008.jpg` | HEAD blob `142ebb0` | Fixture |
| Real photo thumbnail: China_Drone_000085 | `China_Drone_000085.jpg` | HEAD blob `1077c01` | Fixture |
| Real photo thumbnail: minimum crop | `Czech_000010.jpg` | same blob | Fixture |
| Dashboard map: local image renders boxes | `Czech_000010.jpg` | same blob | Fixture |

- Fix: re-include those six tracked paths in the local sparse checkout and check them out from the index. No test assertion was weakened. No image was drawn by hand.
- Tests: the five files, then the full `flutter test`.
- Results: the five files passed (27 tests). The full suite later passed 148/148, which includes one new EXIF case.
- Limitations: a fresh sparse checkout that still excludes `app/test/goldens/images/**` will fail these tests again until those paths are included. The images are the RDD samples already stored in git, not a new dataset.
- Deployment: none.
- Status: VERIFIED.

## P0 — `flutter analyze`

- Problem: 33 info lints, exit 1. No warnings or errors.
- Root cause: unused `dart:typed_data` imports, `const` that the analyzer could prove, one-line `if` bodies, a nullable local whose initializer is non-null, and test locals named with a leading underscore.
- Files: `annotation_renderer.dart`, `drive_awareness_screen.dart`, `model_status_screen.dart`, `settings_screen.dart`, `frame_annotator.dart`, `image_compressor.dart`, `annotated_image.dart`, `nms_test.dart`, `observation_test.dart`, `organization_test.dart`.
- Fix: `dart fix --apply` for those diagnostics only, then `dart format` on the files it changed. No `ignore` comments. No analyzer rule was disabled. `image_compressor.dart` now treats `compressWithList` as non-null, which matches the signature the analyzer saw, and still returns the original bytes when the compressed buffer is empty or the call throws.
- Tests: `flutter analyze`, then `flutter test`.
- Results: `No issues found!` exit 0. 148 tests passed.
- Limitations: none of these edits change detection thresholds or sync rules.
- Status: VERIFIED.

## P0 — SQL migration

- Problem: the unapplied `submit_observation` function accepted a missing observation id (a NULL cast does not throw), a non-UUID child id only failed later as a raw cast, and a missing confidence or box compared as NULL and was not rejected.
- Root cause: `NULLIF`-style absence becomes SQL NULL, and `NULL < 0` is not true.
- Files: `supabase/migrations/20261105_submit_observation_stable_ids.sql`. The previous file was copied to the phase 4 backup first.
- Fix: a null observation id or capture id raises. A non-UUID agent-run or detection id raises before any insert. A null confidence or a null box raises. The client observation id is still stored as `observations.id`. Child ids are still the client UUIDs (the function does not mint UUID v5 and does not call `gen_random_uuid()`). A repeated call with the same ids inserts nothing new. A receipt is still inserted only after the observation, location, and payload children exist. An exception aborts the function, so a failed statement does not keep a partial insert. No `DELETE`. The `GRANT` to `anon` and `authenticated` is unchanged. The function still does not call `auth.uid()`.
- Tests: the existing parser test, plus `evaluation/android_model_audit/scripts/test_submit_observation_pg.py` on database `tariqmap_phase4` only.
- Results: parser tests passed. Local execution: 5 tests passed (repeat, repair, invalid payloads, conflicting child id, class `D99` rolls back). See `PHASE_4_DATABASE_VALIDATION.md`.
- Limitations: the local tables contain only the columns this function inserts. Production may have more `NOT NULL` columns. That was not checked against a production dump. The file was not deployed.
- Deployment: review on staging, then the project's migration path. Do not apply it from this clone. Do not delete old random-id rows.
- Status: VERIFIED on the disposable local database. NOT VERIFIED against production schema or production data.

## P1 — Android SDK and debug APK

- Problem: Phase 3 had Flutter and Java, and no Android SDK, so no APK.
- Root cause: `ANDROID_HOME` was unset and `sdkmanager` was absent.
- Files: SDK unpacked under `$HOME/Android/Sdk` (not in the repo). `app/android/gradle.properties` gained `kotlin.jvm.target.validation.mode=warning`.
- Fix: command-line tools, platform `android-36`, build-tools `35.0.0`, platform-tools, and the CMake the Gradle build requested. `pubspec.yaml` was not edited. The first `flutter build apk --debug` failed in `:tflite_flutter:compileDebugKotlin` because that plugin compiles Java at 1.8 and Kotlin at the Gradle JDK (21). The warning mode lets that existing plugin mismatch through. Plugin versions were not changed. Kotlin stays 2.2.20. Flutter warned that support for 2.2.20 will be dropped; it was not upgraded.
- Tests: `flutter doctor` shows the Android toolchain. `flutter build apk --debug`.
- Results: `app/build/app/outputs/flutter-apk/app-debug.apk` is 442 MB. That path is gitignored. The APK was not installed.
- Limitations: a debug APK is not a release build and was not launched. Emulator launch is BLOCKED: `/dev/kvm` is group `ssl-cert`, and this user is not in that group.
- Deployment: copy the debug APK to a phone with USB debugging. That step was not done here.
- Status: PARTIALLY VERIFIED. The APK exists. Device and emulator runs were not done.

## P1 — Offline sync

- Problem: the simulator did not show several pending rows, a restart, and a child-insert failure repaired on the next attempt.
- Root cause: those sequences were split across other tests or missing.
- Files: `backend/test_offline_recovery.py`.
- Fix: one test creates three local rows, fails the network on the first, fails the child insert on the second, restores stuck `uploading` rows, syncs all three, and syncs the repaired row again.
- Tests: that file, plus the existing Dart `sync_state_test.dart` inside `flutter test`.
- Results: 8 Python tests passed. Dart sync tests passed inside the 148.
- Limitations: the Python types are an in-memory stand-in. They do not open SQLite or Supabase. The Dart coordinator tests use `MemoryObservationRepository` and a mock client.
- Status: VERIFIED for those mocks. Live storage is NOT VERIFIED.

## P1 — EXIF

- Problem: corrupted bytes and a larger photo were not in the Dart file.
- Root cause: Phase 3 covered orientations 1, 3, 6, 8, missing metadata, invalid tag 99, and a small portrait/landscape pair.
- Files: `app/test/unit/exif_orientation_test.dart`.
- Fix: no production change. The new test checks that garbage bytes are returned unchanged by `bytesForUpload` and that `decodeAndOrient` throws `ArgumentError`. A 1280×720 JPEG with orientation 6 becomes 720×1280, a second orient keeps that size, and stretch is still 640×640. An upright 640×480 JPEG is not re-encoded.
- Results: the new test passed inside `flutter test` (148). Pillow EXIF tests still pass (6). There is no static image cache in `preprocessing.dart`. A heap profile was not taken, so “memory released” is NOT VERIFIED as a measurement.
- Status: VERIFIED for the Dart cases that ran. Device capture is NOT VERIFIED.

## P1 — Dashboard and backend

- Problem: confirm Phase 2–3 dashboard and API behavior still holds.
- Root cause: no new dashboard defect was found in this pass.
- Files: none edited for this item.
- Tests: Vitest, `vite build`, `backend.test_api_validation`, `backend.test_sync_recovery`.
- Results: Vitest 93 passed. Vite build succeeded. API validation 6 passed. Sync recovery 11 passed. Unknown is still not D40 in those tests. No accuracy figure was added.
- Limitations: the dashboard was not clicked in a browser.
- Status: VERIFIED for the automated suites. Browser use is NOT VERIFIED.

## P2 — Performance

No bottleneck was measured that justified a detection, query, or upload change. No weights were touched. Host timings are in `PHASE_4_TEST_RESULTS.md` and are not phone timings.

## Status

| Item | Status |
| --- | --- |
| Golden fixtures and the 13 tests | VERIFIED |
| `flutter analyze` | VERIFIED |
| SQL file on disposable Postgres | VERIFIED |
| SQL on production | NOT VERIFIED. Not deployed |
| Debug APK build | PARTIALLY VERIFIED |
| Emulator and device | BLOCKED |
| Offline mocks | VERIFIED |
| EXIF Dart cases | VERIFIED |
| EXIF heap and camera | NOT VERIFIED |
| Dashboard and API suites | VERIFIED |
| Performance change | NOT APPLICABLE |
