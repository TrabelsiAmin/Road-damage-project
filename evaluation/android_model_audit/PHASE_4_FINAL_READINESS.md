# Phase 4 final readiness

HEAD `cd7d168`. Branch `main` matches `origin/main` with a large uncommitted tree. No commit and no push.

## Git

Tracked diff: **46 files, +1991 / −984**. That includes Phase 1–3 edits plus Phase 4 analyzer fixes, the SQL null/UUID checks, `app/android/gradle.properties`, and the EXIF test.

Untracked paths remain the Phase 1–3 additions plus Phase 4 reports and `evaluation/android_model_audit/scripts/test_submit_observation_pg.py`. `git status` shows 46 modified and 24 untracked entries. `evaluation/` is one untracked directory.

Not in the diff: `ios/`, weights (`.tflite`, `.pt`, `.onnx`), datasets, `.env` files, and the debug APK. `app/build/`, `app/android/local.properties`, and `dashboard/dist` are gitignored. `app/pubspec.yaml` was not edited. `app/pubspec.lock` still has the Phase 3 transitive resolver change.

No test was marked skip. Analyzer rules were not disabled.

Phase 2 and Phase 3 reports are still under `evaluation/android_model_audit/`.

## Suite rollup

| Suite | Status |
| --- | --- |
| Training contracts | Passed (2) |
| Tensor / stretch contract | Passed |
| Decoder math | Passed |
| Flutter test | Passed (148) |
| Flutter analyze | Passed (0 issues) |
| Pillow EXIF | Passed (6) |
| Dart EXIF, including the new large and corrupted cases | Passed inside the 148 |
| Sync mocks | Passed (8 Python, plus Dart sync tests) |
| SQL parser contract | Passed (3) |
| SQL execution on local `tariqmap_phase4` | Passed (5) |
| Backend API | Passed (6) |
| Backend sync recovery | Passed (11) |
| Dashboard Vitest | Passed (93) |
| Dashboard build | Passed |
| Debug APK | Built, not installed |
| Emulator | Blocked. No KVM access |
| Production Supabase | Not executed |

## Ready for a person to install a debug build on a phone

The debug APK builds. Analyzer is clean. The Flutter suite passes when the golden JPEGs are checked out. Stretch is still the Android path for `road_damage.tflite`.

That is not a finished device test. Nobody has opened the camera, confirmed a box on a real preview, or timed inference on a phone. The emulator could not be started here.

## Not ready to treat as scientifically or operationally finished

- The model is still not scientifically validated. No mAP was computed.
- The new `submit_observation` function passed a disposable Postgres harness and is not deployed. Production may still be running the old function, which returns early and can mint random child ids.
- RLS recommendations are still comments and were not applied. The anon key and env vars do not replace those policies.
- Unknown codes still fail the SQL class check and stay on the device.
- Kotlin 2.2.20 is the version Flutter warned about. It was left in place so dependency versions stayed put.
- A checkout that uses the sparse exclusion of `app/test/goldens/images/` will fail 13 tests until those tracked JPEGs are materialized.

## Status

| Question | Status |
| --- | --- |
| Android debug build exists | PARTIALLY VERIFIED |
| Safe to start a supervised phone test of that APK | Yes, as a manual test, not as a claim that this environment already passed it |
| Ready to ship the SQL migration or call the model validated | No |
