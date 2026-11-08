# Pre-UI change review

Read-only audit on 2026-11-07. One new file: this report. No other file was edited. Nothing was staged, committed, or pushed. `git fetch origin main` completed and did not change the working tree.

## Git

| Item | Value |
| --- | --- |
| Branch | `main` |
| HEAD | `cd7d16898465174c06a1362953c052f156e0485b` (`Fix Leaflet map layout and rendering`) |
| Remote | `origin` `https://github.com/TrabelsiAmin/Road-damage-project.git` (partial clone, `blob:none`) |
| Upstream | `main...origin/main` |
| After fetch | `HEAD` and `origin/main` are the same commit. `git rev-list --left-right --count HEAD...origin/main` is `0 0` |
| Tracked diff | 51 files, +2085 / −996 |
| `git status --short` | 51 modified, 26 untracked lines |
| Expanded untracked | 197 files before this report. `evaluation/` is one of those 26 lines |

`.tflite` files have an empty `git diff --stat`. `ios/` has no status lines. `app/build/` and `app/.dart_tool/` are gitignored.

Do not push this branch. `main` tracks `origin/main`. A later publish needs a new branch, created only after the user confirms. This audit did not create one.

## Secrets in the diff

No passwords, keystores, or service-role keys were added.

| File | Kind | Note |
| --- | --- | --- |
| `dashboard/src/supabase.js` | Supabase anon JWT and project URL | The added lines contain a 208-character anon JWT. HEAD already has a JWT of the same length. The new code uses it only when `import.meta.env.DEV` is true |
| `app/lib/core/supabase_config.dart` | Project URL in the added lines; anon JWT still in the file | The token line is unchanged from HEAD. Release builds return an empty config unless `--dart-define` is set. Debug mode still falls back to the embedded anon key |
| `evaluation/android_model_audit/backups/supabase.js`, `backups/supabase_config.dart`, and the phase2/phase3 copies | Same anon JWT | Copies of older sources. Do not publish the backup tree |
| `backend/.env.example` | None added | The diff removes the real project URL and leaves placeholders |
| `dashboard/.env.example`, `app/dart_defines.example.json`, `app/android/key.properties.example` | Placeholders only | Empty or `your-…` values |
| `app/test/unit/sync_plan_test.dart`, `backend/test_api_validation.py`, `backend/test_sync_recovery.py` | Short synthetic JWT-shaped strings (lengths 70, 70, and 54) | Redaction fixtures, not the anon key |

`test_supabase.py` already contains a 208-character anon JWT on HEAD. This audit did not modify that file.

## Generated files

| Path | Size | Publish |
| --- | --- | --- |
| `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | 162,451,078 | No. Gitignored. Signed `CN=Android Debug` in Phase 6/7 |
| `app/build/app/outputs/bundle/release/app-release.aab` | 231,089,677 | No |
| `app-armeabi-v7a-release.apk` | 196,029,608 | No |
| `app-x86_64-release.apk` | 172,736,264 | No |
| `app-debug.apk` (two copies) | 462,551,570 each | No |
| `app/.dart_tool/` | gitignored | No |
| `evaluation/.../__pycache__/` (10 `.pyc` files) | ignored by `git ls-files --others --exclude-standard` | No |
| `app/pubspec.lock` | six transitive version bumps | See Flutter group. Not an APK |

Lock bumps: `characters` 1.4.0→1.4.1, `matcher` 0.12.17→0.12.20, `material_color_utilities` 0.11.1→0.13.0, `meta` 1.17.0→1.19.0, `test_api` 0.7.7→0.7.12, `vector_math` 2.2.0→2.4.4. `pubspec.yaml` did not change dependency constraints. It only dropped a second asset line for `road_damage_roadsense.tflite`. The file remains inside `assets/models/`, so both models stay bundled.

## KEEP

Host tests from Phase 11 cover these groups. Those results were not re-run for this audit.

### Flutter and Android application

Useful: release signing is selected only when all four values are set, and a missing keystore fails `validateSigningRelease` (Phase 6). Kotlin 2.3.20 matches the Flutter 3.47.9 compiler that previously failed on `kotlinOptions`. Manifest sets `allowBackup=false`, `usesCleartextTraffic=false`, and removes merged `RECORD_AUDIO`. EXIF orientation is applied before stretch. Unknown class codes display `Unknown class` instead of being rewritten to D40. Confidence floors stay D00/D10 0.35, D20 0.30, D40 0.40 until a saved slider value in 0.10–0.80 replaces every class. NMS IoU stays 0.45. Camera, queue, and startup screens record failures instead of failing silently. Sync planning and secret redaction live in small new units.

Last recorded: `flutter analyze` clean, `flutter test` 149/149 (Phase 11).

Limitations: no device or emulator pass. Class mapping UNKNOWN. Release artifacts on disk are debug-signed. Gradle 8.14 and AGP 8.11.1 still warn that newer versions exist. Kotlin was upgraded; those two were left.

Files:

- `app/.gitignore`
- `app/android/app/build.gradle.kts`
- `app/android/app/src/main/AndroidManifest.xml`
- `app/android/gradle.properties`
- `app/android/settings.gradle.kts`
- `app/android/key.properties.example`
- `app/pubspec.yaml`
- `app/lib/inference/annotation_renderer.dart`
- `app/lib/inference/preprocessing.dart`
- `app/lib/inference/confidence_threshold.dart` (new)
- `app/lib/inference/legacy_decoder.dart` (new)
- `app/lib/core/class_codes.dart` (new)
- `app/lib/services/sync_plan.dart` (new)
- `app/lib/services/frame_annotator.dart`
- `app/lib/services/image_compressor.dart`
- `app/lib/services/observation_repository.dart`
- `app/lib/services/tflite_agent_runner.dart`
- `app/lib/data/remote/api_client.dart`
- `app/lib/data/remote/supabase_service.dart`
- `app/lib/models/upcoming_anomaly.dart`
- `app/lib/main.dart`
- `app/lib/screens/camera_detection_screen.dart`
- `app/lib/screens/drive_awareness_screen.dart`
- `app/lib/screens/home_screen.dart`
- `app/lib/screens/model_status_screen.dart`
- `app/lib/screens/offline_queue_screen.dart`
- `app/lib/screens/result_screen.dart`
- `app/lib/screens/settings_screen.dart`
- `app/lib/widgets/annotated_image.dart`
- `app/lib/widgets/dashboard_map.dart`
- `app/dart_defines.example.json` (new)

### Backend

Useful: request validation drops image bodies and JWT-shaped strings from error responses. Field lengths and numeric ranges are bounded. Store helpers redact JWT-shaped text and can tell an existing row from a new one. `.env.example` no longer carries the real project URL.

Last recorded: Python 49 passed in Phase 11, which includes `backend.test_api_validation`, `backend.test_sync_recovery`, and `backend.test_offline_recovery`.

Files: `backend/.env.example`, `backend/main.py`, `backend/schemas.py`, `backend/supabase_store.py`.

### Dashboard

Useful: observations page instead of one unbounded read. Unknown classes are not counted as D40. Data-quality copy says stored confidence is not precision, recall, or mAP. Empty metric states are visible.

Last recorded: vitest 93, Vite production build OK (Phase 11).

Files: `dashboard/.env.example`, `dashboard/src/App.jsx`, `dashboard/src/index.css`, `dashboard/src/components/ActionCenterView.jsx`, `dashboard/src/components/CaseDetailModal.jsx`, `dashboard/src/components/DataQualityView.jsx`, `dashboard/src/components/RoadSegmentRiskView.jsx`, `dashboard/src/components/layout/Topbar.jsx`, `dashboard/src/utils/clustering.js`, `dashboard/src/utils/commandCenterAnalytics.js`, `dashboard/src/utils/exportFormats.js`, `dashboard/src/utils/ministryAnalytics.js`, `dashboard/src/utils/roadSegmentRisk.js`, plus new `dashboard/src/utils/classCodes.js` and `dashboard/src/utils/records.js`.

### Tests

Keep each test with the area it covers.

Flutter: `app/test/unit/nms_test.dart`, `observation_test.dart`, `organization_test.dart`, and new `class_codes_test.dart`, `confidence_threshold_test.dart`, `exif_orientation_test.dart`, `legacy_decoder_test.dart`, `legacy_stretch_contract_test.dart`, `model_asset_test.dart`, `sync_plan_test.dart`.

Backend: `backend/test_api_validation.py`, `backend/test_offline_recovery.py`, `backend/test_sync_recovery.py`.

Dashboard: `dashboard/src/utils/commandCenterAnalytics.test.js`, and new `supabaseConfig.test.js`, `analyticsConsistency.test.js`, `classCodes.test.js`, `metricsHonesty.test.js`, `records.test.js`.

Python contract tools, with the docs commit: `evaluation/android_model_audit/scripts/` except `__pycache__`. Phase 11 also recorded SQL contract OK and spec math OK.

### Documentation worth keeping

`test_images.py` and `test_single_image.py` only add comments that the Crack/Pothole/Rutting/Uneven-Surface strings are not a proven class map.

Phase reports and the annotation schema, validator, split tool, and readiness gate are the audit record. They do not claim a measured mAP. `METRICS.json` is an audit file with null scores, not a result.

## REVIEW

| Path | Why it is not an automatic keep |
| --- | --- |
| `app/lib/core/supabase_config.dart` | Behavior is an improvement (debug-only fallback, refuse a service-role JWT). The file still embeds an anon JWT. Decide whether to keep that debug fallback before publishing |
| `dashboard/src/supabase.js` | Same decision. The patch repeats the anon JWT |
| `app/pubspec.lock` | Transitive Flutter SDK noise from 3.47.9, not a chosen upgrade. Include it with the app commit so the lock matches that SDK, or leave it out and let the next `flutter pub get` rewrite it |
| `app/lib/screens/settings_screen.dart` | Largest UI diff (+437/−185 in the file stat). A later UI phase will touch this screen. Read it before restyling |
| `supabase/migrations/20261105_submit_observation_stable_ids.sql` | The text is a real proposal and says NOT APPLIED. A tool that applies every file in `supabase/migrations` would send it to production. Do not commit it there until someone approves that. It was executed only on disposable local database `tariqmap_phase4` |
| `supabase/recommended/rls_and_storage_NOT_APPLIED.sql` | Comments and an intentionally non-runnable sketch. Safe as a note. Do not treat it as a migration |
| `evaluation/android_model_audit/*.md` and `schema/` | Publish only if the audit trail belongs in the product repo. It is not required for the app to build |

## EXCLUDE

- `evaluation/android_model_audit/backups/` (about 1.3 MB). Older copies, including anon JWTs. The live tree is the source.
- `evaluation/**/__pycache__/` and `backend/__pycache__/`.
- `app/build/**`, every APK, and the AAB.
- `app/.dart_tool/`.
- `app/android/key.properties`, `*.jks`, `*.keystore`. None of these exist. The example file is the one that may be committed.
- Model weights. Unmodified. Do not re-add or replace them.

## Risks

- No ARM64 install, launch, camera, offline, or retry pass.
- Class mapping UNKNOWN. Zero label files. Scientific metrics were not computed.
- Production Supabase was not migrated and has no recorded security approval.
- The on-disk AAB is debug-signed.
- Shipping stable client ids before the SQL function is deployed is unverified against production. This audit did not read the production function.
- Debug anon keys remain in two client files and in backups.

## Proposed commits

Not executed. Create a branch first. Suggested name only: `cursor/pre-ui-audit-publish`. Do not commit to `main`.

Order: mobile, backend, dashboard, tests that were not already included, documentation. Tests below are listed in their own commit so each area stays reviewable. Push the branch once, after every commit, so the remote never has the code without its tests.

### 1. `Keep both models and select an upload key only when configured.`

`app/.gitignore`, `app/android/app/build.gradle.kts`, `app/android/app/src/main/AndroidManifest.xml`, `app/android/gradle.properties`, `app/android/settings.gradle.kts`, `app/android/key.properties.example`, `app/pubspec.yaml`, and `app/pubspec.lock` if the lock bump is accepted.

### 2. `Fail closed on unknown classes, EXIF orientation, and sync errors.`

Every `app/lib/**` path in KEEP, plus `app/dart_defines.example.json`. Hold `supabase_config.dart` out until the debug-key decision, or include it in this commit after that decision.

### 3. `Bound observation writes and redact tokens in API errors.`

`backend/.env.example`, `backend/main.py`, `backend/schemas.py`, `backend/supabase_store.py`. Omit the SQL migration.

### 4. `Page dashboard observations and stop treating unknown classes as D40.`

Every dashboard KEEP path except `dashboard/src/supabase.js` until the same key decision. Include that file in this commit if the debug fallback stays.

### 5. `Add host tests for thresholds, sync, class codes, and dashboard honesty.`

All Flutter, backend, and dashboard test paths listed under KEEP.

### 6. `Record the model audit and the annotation gate.`

`test_images.py`, `test_single_image.py`, and `evaluation/android_model_audit/` except `backups/` and `__pycache__`. Omit this report until it exists, then add it in the same commit if the audit trail is published. Omit `supabase/migrations/20261105_submit_observation_stable_ids.sql` unless it is moved out of the auto-applied migrations directory first.

## Commands

NOT EXECUTED:

```bash
cd /tmp/Road-damage-project
git checkout -b cursor/pre-ui-audit-publish
# git add <paths for one commit>
# git commit -m "<message above>"
# repeat per commit
git push -u origin cursor/pre-ui-audit-publish
```

Do not run `git push origin main`.
