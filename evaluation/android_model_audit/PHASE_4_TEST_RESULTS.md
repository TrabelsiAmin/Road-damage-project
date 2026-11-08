# Phase 4 test results

Clone: `/tmp/Road-damage-project`. HEAD: `cd7d168`. Nothing was committed or pushed. No production Supabase call was made. `test_rls.py`, `test_supabase.py`, `test_sync_simulation.py`, and `training/test_rls.py` were not executed.

Host: Linux, Flutter 3.47.9, Dart 3.13.7, Java 21.0.12, PostgreSQL 16.15. Android SDK at `$HOME/Android/Sdk` with platform `android-36`, build-tools `35.0.0`, and platform-tools. `adb` is 1.0.41. `/dev/kvm` exists and is not writable by this user.

## Passed

| Suite | Result |
| --- | --- |
| Training contracts `training.tests.test_contracts` | 2 passed |
| Tensor / stretch contract `lock_android_contract.py` | `CONTRACT OK` |
| Decoder math `spec_decoder_math.py` | `SPEC MATH OK` |
| Pillow EXIF `test_exif_orientations.py` | 6 passed |
| SQL parser contract `test_sql_id_contract.py` | 3 passed |
| SQL execution `test_submit_observation_pg.py` on `tariqmap_phase4` | 5 passed in the combined 16-test run with the parser and offline tests |
| Offline recovery `backend/test_offline_recovery.py` | 8 passed |
| Backend API validation | 6 passed |
| Backend sync recovery | 11 passed |
| Dashboard Vitest | 19 files, 93 passed |
| Dashboard `vite build` | succeeded |
| `flutter analyze` | `No issues found!` exit 0 |
| `flutter test` | 148 passed, 0 failed. About 16 seconds on this host |
| `dart format --output=none --set-exit-if-changed` on the Dart files this phase formatted | exit 0 |

The 148 includes the previous 134, the 13 fixture tests, and the new corrupted-bytes / 1280×720 EXIF test. No test was skipped or given a weaker assertion.

`flutter doctor` reports the Android toolchain as present and licenses accepted. The Linux desktop toolchain is missing ninja and GTK. That target was not built.

## Failed

None in the suites above.

## Blocked

| Suite | Reason |
| --- | --- |
| Emulator | `/dev/kvm` is `crw-rw---- root:ssl-cert`. This user is not in `ssl-cert` or group 103. An emulator was not started. Software emulation was not used as a substitute. |
| Device install | No phone was attached. `adb devices` was not a passing device test. The debug APK was built and not installed. |
| Production SQL | Not run. The local database name is `tariqmap_phase4`. |

## Not executed

- Live Supabase RLS and sync scripts listed above.
- `flutter build apk --release`.
- A browser pass of the dashboard.
- A heap profile of EXIF decode.
- A phone timing run.

## Debug APK

`flutter build apk --debug` exited 0 after `kotlin.jvm.target.validation.mode=warning` was set. Output: `app/build/app/outputs/flutter-apk/app-debug.apk`, 442 MB. The first build, before that Gradle flag, failed in `:tflite_flutter:compileDebugKotlin` (Java 1.8 vs Kotlin JVM 21). The APK was not launched, so this is a build result, not a device pass.

## Notes

- Sparse checkout must include `app/test/goldens/images/` or the 13 image tests fail again even though the blobs are in git.
- `app/pubspec.lock` is still the Phase 3 resolver update. `pubspec.yaml` was not edited in Phase 4.
- Flutter printed a warning that Kotlin 2.2.20 will soon be unsupported. The Kotlin version was not changed.
