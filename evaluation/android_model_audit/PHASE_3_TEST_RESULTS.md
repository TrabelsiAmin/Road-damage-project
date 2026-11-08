# Phase 3 test results

Clone: `/tmp/Road-damage-project`. HEAD: `cd7d168`. Nothing was committed or pushed. No live Supabase call was made. `test_rls.py`, `test_supabase.py`, `test_sync_simulation.py`, and `training/test_rls.py` were not executed.

Environment for the Dart run: Flutter 3.47.9 stable, Dart 3.13.7, Java 21.0.12. `adb` is absent. `ANDROID_HOME` is unset. No Android SDK directory and no emulator binary were found. The Flutter SDK was unpacked to `$HOME/sdk/flutter` for this run. `app/pubspec.yaml` was not edited. `flutter pub get` did change `app/pubspec.lock`.

## Passed

| Suite | Command | Result |
| --- | --- | --- |
| Training contracts | `python3 -m unittest training.tests.test_contracts` | 2 passed |
| Android stretch contract | `python3 evaluation/android_model_audit/scripts/lock_android_contract.py` | `CONTRACT OK` |
| Decoder math | `python3 evaluation/android_model_audit/scripts/spec_decoder_math.py` | `SPEC MATH OK` |
| Pillow EXIF supplement | `python3 -m unittest evaluation.android_model_audit.scripts.test_exif_orientations` | 6 passed |
| Duplicate diagnostic | `python3 -m unittest evaluation.android_model_audit.scripts.test_duplicate_diagnostic` | 3 passed |
| SQL id contract | `python3 -m unittest evaluation.android_model_audit.scripts.test_sql_id_contract` | 3 passed |
| Backend API validation | `python3 -m unittest backend.test_api_validation` | 6 passed |
| Backend sync recovery | `python3 -m unittest backend.test_sync_recovery` | 11 passed |
| Offline recovery simulator | `python3 -m unittest backend.test_offline_recovery` | 7 passed |
| Dashboard | `npm test -- --run` in `dashboard/` | 19 files, 93 tests passed |
| Dashboard production build | `npm run build` (Vite 6.4.4) | succeeded |
| Edited Dart format | `dart format --output=none --set-exit-if-changed` on the nine edited Dart files | exit 0 after formatting `preprocessing.dart` |
| Phase 2/3 Dart unit files inside the full run | class codes, confidence, EXIF, sync plan, legacy decoder, stretch, sync state | passed; they are not in the failure list |

The Python suites above were run together as 32 tests and all passed. Counts are the `test_` methods in each file.

Production bundle check after the Vite build: concatenated JS is 724,609 bytes. The project ref `lendqcjihusqkmxansbl` is absent. The substring `eyJ` is absent. The word `service_role` is present because the client compares that role name and refuses it. No service-role secret was printed or found as a JWT.

## Failed

`flutter test` in `app/`: **134 passed, 13 failed**. Exit is non-zero. The failures are missing fixtures. Tests were not edited to skip them, and no fixture images were added.

1. `detection_pipeline_test.dart` — known crack image through the pipeline. Fixture image is absent.
2. `detection_pipeline_test.dart` — null dimensions resolve on save. Fixture image is absent.
3. `thumbnail_sync_test.dart` — skips thumbnail when there is no detection.
4. `thumbnail_sync_test.dart` — Option A crop, margin blur, size limits.
5. `thumbnail_sync_test.dart` — minimum crop and aspect ratio.
6. `thumbnail_sync_test.dart` — minimum crop when the box is below 0.5%.
7. `roadsense_decoder_test.dart` — letterbox golden geometry across 5 images. Goldens are absent. Stretch was not changed to letterbox to make this pass. RoadSense stays off unless `USE_ROADSENSE_MODEL`.
8. `roadsense_decoder_test.dart` — `imageToNchwFloat32` tensor. Golden is absent.
9. `real_photo_thumbnail_test.dart` — `Czech_000010.jpg`.
10. `real_photo_thumbnail_test.dart` — `Japan_000008.jpg`.
11. `real_photo_thumbnail_test.dart` — `China_Drone_000085.jpg`.
12. `real_photo_thumbnail_test.dart` — minimum crop case. `PathNotFoundException` for `test/goldens/images/Czech_000010.jpg`.
13. `dashboard_map_test.dart` — local image fixture must exist (`Expected: true, Actual: <false>`).

`flutter analyze` in `app/`: **33 info issues, 0 warnings, 0 errors, exit 1**. Flutter's default treats info as a failing exit. The remaining infos are pre-existing style lints (`prefer_const_constructors`, `prefer_const_declarations`, `unnecessary_import`, `no_leading_underscores_for_local_identifiers`, `unnecessary_nullable_for_final_variable_declarations`) and one pre-existing brace lint at `lib/screens/settings_screen.dart:220`. They were not mass-fixed. Two earlier warnings (`existing is List` always true, and `value is int` always true) were removed before this analyze.

## Blocked

| Item | Reason |
| --- | --- |
| Debug APK | No Android SDK. `sdkmanager` and a platform directory are not present. |
| Emulator or device tests | No `adb`, no emulator binary, `ANDROID_HOME` unset. Static analysis and `flutter test` are not device tests. |
| Applying `20261105_submit_observation_stable_ids.sql` | Forbidden. The file is unapplied. Contract coverage is the local parser and the in-memory planner. |
| Applying `supabase/recommended/rls_and_storage_NOT_APPLIED.sql` | Forbidden. The file is comments and is not in `supabase/migrations`. |
| Production duplicate report | The classifier was run on synthetic rows only. |
| Browser click of Load older | Vitest and the Vite build ran. No browser session clicked the banner. |
| Settings widget pump | The threshold sentence is unit-tested. The settings screen was not pumped. |

## Not executed

- Live Supabase: `test_rls.py`, `training/test_rls.py`, `test_supabase.py`, `test_sync_simulation.py`.
- `supabase db push`, `psql`, or any other production or staging SQL.
- `flutter build apk`.
- A device camera EXIF capture.
- A phone timing run for the interpreter, decode memory, or upload size.

## Notes that are not passes

- The SQL tests strip `--` and `/* */` comments before asserting that executable SQL has no `gen_random_uuid()` and no `DELETE FROM`. The migration comment still names the old function. That is intentional.
- Pillow EXIF tests supplement the Dart tests. They are not a substitute. The Dart EXIF tests did run and passed.
- `app/pubspec.lock` changed under the Flutter 3.47.9 resolver. Direct versions in `pubspec.yaml` did not. The test run used the updated lock.
