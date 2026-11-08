# Publish staging plan

Branch `cursor/pre-ui-audit-publish` was created from `main` at `cd7d16898465174c06a1362953c052f156e0485b`. The working tree was carried along. The branch has no upstream. Nothing in this plan has been staged, committed, or pushed.

`git status --short` is still 51 modified and 26 untracked lines. The path set after `git switch -c` matched the set recorded on `main`.

Five groups. Six commits. The SQL migration is held, not a commit.

| Commit | Group |
| --- | --- |
| 1 and 2 | Flutter/Android reliability |
| 3 | Backend validation and synchronization |
| 4 | Admin dashboard |
| 5 | Automated tests |
| 6 | Model audit and annotation tooling |

## Secrets

No service-role credential is in the publish set. `backend/.env.example` and `dashboard/.env.example` are placeholders (`https://your-project.supabase.co`, `your-service-role-key`, `your-anon-key`). `app/dart_defines.example.json` and `app/android/key.properties.example` are placeholders. No keystore file exists.

| File | Working tree vs HEAD | JWT role claim |
| --- | --- | --- |
| `app/lib/core/supabase_config.dart` | The single JWT equals HEAD | `anon` |
| `dashboard/src/supabase.js` | The single JWT equals HEAD | `anon` |

REVIEW: publishing those diffs does not introduce a new secret. It continues to ship the public anon key already on HEAD. Release Flutter uses it only in `kDebugMode`. The dashboard uses it only when `import.meta.env.DEV` is true. The Vite production build from this run contains the word `service_role` (the refusal check) and does not contain `eyJ`.

Other JWT-shaped strings in the publish set are synthetic: `app/test/unit/sync_plan_test.dart` role `test` (length 70), `backend/test_api_validation.py` role `test` (length 70), `backend/test_sync_recovery.py` not a decodable JWT (length 54). `test_supabase.py` already on HEAD contains an anon JWT and is not part of these commits. Backup copies of the anon JWT stay excluded.

## settings_screen.dart

INCLUDE in commit 2. The diff is the approved confidence-slider contract, not a restyle to drop:

- Loads `confidence_threshold_set`. Until that flag is true, class floors stay in force.
- Clamps the stored and drafted values through `clampConfidenceThreshold`.
- Slider limits are `confidenceSliderMin` and `confidenceSliderMax` (0.10 and 0.80).
- Save writes the clamped double and sets `confidence_threshold_set`.
- The description says a slider preview is not applied until Save.
- Wi-Fi, retention, and organization rows keep their previous prefs. Surrounding lines were rewrapped.

## Held

| Path | Why |
| --- | --- |
| `supabase/migrations/20261105_submit_observation_stable_ids.sql` | A migration runner that applies `supabase/migrations` would change production. Tested only on disposable local database `tariqmap_phase4`. |
| `supabase/recommended/rls_and_storage_NOT_APPLIED.sql` | SQL-shaped policy text. Not approved. Left out so it is not copied into migrations by mistake. The body is comments and is not valid to run alone. |
| `evaluation/android_model_audit/scripts/test_sql_id_contract.py` | Reads the held migration. A clone without that file would fail this test. |
| `evaluation/android_model_audit/scripts/test_submit_observation_pg.py` | Applies that migration when `PHASE4_LOCAL_PG_URL` contains `phase4`. Left with the SQL. This run did not set that variable. The test skipped. PostgreSQL was not contacted. |

The Flutter and backend stable-id code stays in the publish set. It writes UUID v5 ids on the client and in `SupabaseStore` direct inserts. It does not execute the held SQL. The existing RPC used `gen_random_uuid()` only when a child id was absent. These clients always send an id. That is safe to publish without the migration. Production behavior of the live function was not re-read.

## Excluded

- `evaluation/android_model_audit/backups/` (anon JWT copies and old sources)
- `**/__pycache__/`, `app/build/`, `app/.dart_tool/`, `dashboard/dist/`
- APK and AAB files under `app/build/app/outputs/` (arm64 APK 162,451,078 bytes, AAB 231,089,677 bytes). Gitignored.
- `app/android/key.properties`, `*.jks`, `*.keystore` (none present)

Do not `git add evaluation/android_model_audit` as a directory. That would stage `backups/`.

## Tests this run

Not an Android rebuild.

| Suite | Result |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter test` | 149 passed |
| Python unittest of the Phase 11 modules | 49 passed. That is 36 plus 13 tool tests |
| `test_submit_observation_pg` | skipped, 0 ran. URL unset |
| `lock_android_contract.py` | CONTRACT OK |
| `spec_decoder_math.py` | SPEC MATH OK |
| dashboard vitest | 19 files, 93 tests passed |
| `npm run build` | built |

## Commands

NOT EXECUTED. Do not push `main`. After the commits, a later push would be `git push -u origin cursor/pre-ui-audit-publish`.

```bash
cd /tmp/Road-damage-project
# already on cursor/pre-ui-audit-publish
```

### Commit 1 — Flutter/Android reliability

`Keep both models and select an upload key only when configured.`

```bash
git add -- \
  app/.gitignore \
  app/android/app/build.gradle.kts \
  app/android/app/src/main/AndroidManifest.xml \
  app/android/gradle.properties \
  app/android/settings.gradle.kts \
  app/android/key.properties.example \
  app/pubspec.yaml \
  app/pubspec.lock
```

Omitted: Dart sources, SQL, backups, build outputs. `pubspec.lock` is the six transitive Flutter 3.47.9 bumps, included so the lock matches that SDK. `pubspec.yaml` only removes a duplicate asset line. Both `.tflite` files stay bundled and are unmodified.

### Commit 2 — Flutter/Android reliability

`Fail closed on unknown classes, EXIF orientation, and sync errors.`

Includes `settings_screen.dart` (see above) and `supabase_config.dart` (same anon key as HEAD, role `anon`).

```bash
git add -- \
  app/dart_defines.example.json \
  app/lib/core/class_codes.dart \
  app/lib/core/supabase_config.dart \
  app/lib/data/remote/api_client.dart \
  app/lib/data/remote/supabase_service.dart \
  app/lib/inference/annotation_renderer.dart \
  app/lib/inference/confidence_threshold.dart \
  app/lib/inference/legacy_decoder.dart \
  app/lib/inference/preprocessing.dart \
  app/lib/main.dart \
  app/lib/models/upcoming_anomaly.dart \
  app/lib/screens/camera_detection_screen.dart \
  app/lib/screens/drive_awareness_screen.dart \
  app/lib/screens/home_screen.dart \
  app/lib/screens/model_status_screen.dart \
  app/lib/screens/offline_queue_screen.dart \
  app/lib/screens/result_screen.dart \
  app/lib/screens/settings_screen.dart \
  app/lib/services/frame_annotator.dart \
  app/lib/services/image_compressor.dart \
  app/lib/services/observation_repository.dart \
  app/lib/services/sync_plan.dart \
  app/lib/services/tflite_agent_runner.dart \
  app/lib/widgets/annotated_image.dart \
  app/lib/widgets/dashboard_map.dart
```

### Commit 3 — Backend validation and synchronization

`Bound observation writes and redact tokens in API errors.`

```bash
git add -- \
  backend/.env.example \
  backend/main.py \
  backend/schemas.py \
  backend/supabase_store.py
```

Omitted: the held SQL files and the two scripts that read or apply them.

### Commit 4 — Admin dashboard

`Page dashboard observations and stop treating unknown classes as D40.`

Includes `dashboard/src/supabase.js` (same anon key as HEAD, role `anon`).

```bash
git add -- \
  dashboard/.env.example \
  dashboard/src/App.jsx \
  dashboard/src/index.css \
  dashboard/src/supabase.js \
  dashboard/src/components/ActionCenterView.jsx \
  dashboard/src/components/CaseDetailModal.jsx \
  dashboard/src/components/DataQualityView.jsx \
  dashboard/src/components/RoadSegmentRiskView.jsx \
  dashboard/src/components/layout/Topbar.jsx \
  dashboard/src/utils/classCodes.js \
  dashboard/src/utils/clustering.js \
  dashboard/src/utils/commandCenterAnalytics.js \
  dashboard/src/utils/exportFormats.js \
  dashboard/src/utils/ministryAnalytics.js \
  dashboard/src/utils/records.js \
  dashboard/src/utils/roadSegmentRisk.js
```

Omitted: dashboard tests (commit 5) and `dashboard/dist`.

### Commit 5 — Automated tests

`Add host tests for thresholds, sync, class codes, and dashboard honesty.`

```bash
git add -- \
  app/test/unit/class_codes_test.dart \
  app/test/unit/confidence_threshold_test.dart \
  app/test/unit/exif_orientation_test.dart \
  app/test/unit/legacy_decoder_test.dart \
  app/test/unit/legacy_stretch_contract_test.dart \
  app/test/unit/model_asset_test.dart \
  app/test/unit/nms_test.dart \
  app/test/unit/observation_test.dart \
  app/test/unit/organization_test.dart \
  app/test/unit/sync_plan_test.dart \
  backend/test_api_validation.py \
  backend/test_offline_recovery.py \
  backend/test_sync_recovery.py \
  dashboard/src/supabaseConfig.test.js \
  dashboard/src/utils/analyticsConsistency.test.js \
  dashboard/src/utils/classCodes.test.js \
  dashboard/src/utils/commandCenterAnalytics.test.js \
  dashboard/src/utils/metricsHonesty.test.js \
  dashboard/src/utils/records.test.js
```

Omitted: `test_sql_id_contract.py` and `test_submit_observation_pg.py`.

### Commit 6 — Model audit and annotation tooling

`Record the model audit and the annotation gate.`

```bash
git add -- \
  test_images.py \
  test_single_image.py \
  evaluation/android_model_audit/ACCURACY_EVALUATION.md \
  evaluation/android_model_audit/ANDROID_PERFORMANCE.md \
  evaluation/android_model_audit/CHANGES_LOG.md \
  evaluation/android_model_audit/CLASS_MAPPING.md \
  evaluation/android_model_audit/DATASET_AUDIT.md \
  evaluation/android_model_audit/END_TO_END_TESTS.md \
  evaluation/android_model_audit/EXECUTIVE_SUMMARY.md \
  evaluation/android_model_audit/IMPLEMENTATION_REPORT.md \
  evaluation/android_model_audit/METRICS.csv \
  evaluation/android_model_audit/METRICS.json \
  evaluation/android_model_audit/MODEL_ARCHITECTURE.md \
  evaluation/android_model_audit/PHASE_10_DATASET_TOOLING_AUDIT.md \
  evaluation/android_model_audit/PHASE_10_FINAL_READINESS.md \
  evaluation/android_model_audit/PHASE_10_REGRESSION_AUDIT.md \
  evaluation/android_model_audit/PHASE_10_SECURITY_REVIEW.md \
  evaluation/android_model_audit/PHASE_10_WORKTREE_INVENTORY.md \
  evaluation/android_model_audit/PHASE_11_ANDROID_SETUP_GUIDE.md \
  evaluation/android_model_audit/PHASE_11_DATASET_HANDOFF.md \
  evaluation/android_model_audit/PHASE_11_FINAL_ACCEPTANCE_CHECKLIST.md \
  evaluation/android_model_audit/PHASE_11_MANUAL_TEST_PROTOCOL.md \
  evaluation/android_model_audit/PHASE_11_RELEASE_SIGNING_GUIDE.md \
  evaluation/android_model_audit/PHASE_12_ANDROID_EVIDENCE.md \
  evaluation/android_model_audit/PHASE_12_EXTERNAL_VALIDATION_REPORT.md \
  evaluation/android_model_audit/PHASE_12_FINAL_READINESS.md \
  evaluation/android_model_audit/PHASE_12_SCIENTIFIC_EVALUATION.md \
  evaluation/android_model_audit/PHASE_12_SIGNING_VERIFICATION.md \
  evaluation/android_model_audit/PHASE_13_EXTERNAL_EVIDENCE.md \
  evaluation/android_model_audit/PHASE_2_IMPLEMENTATION_REPORT.md \
  evaluation/android_model_audit/PHASE_2_PENDING_DECISIONS.md \
  evaluation/android_model_audit/PHASE_2_SECURITY_REVIEW.md \
  evaluation/android_model_audit/PHASE_2_TEST_RESULTS.md \
  evaluation/android_model_audit/PHASE_3_IMPLEMENTATION_REPORT.md \
  evaluation/android_model_audit/PHASE_3_PENDING_DECISIONS.md \
  evaluation/android_model_audit/PHASE_3_PERFORMANCE_REPORT.md \
  evaluation/android_model_audit/PHASE_3_SECURITY_REVIEW.md \
  evaluation/android_model_audit/PHASE_3_TEST_RESULTS.md \
  evaluation/android_model_audit/PHASE_4_ANDROID_VALIDATION.md \
  evaluation/android_model_audit/PHASE_4_DATABASE_VALIDATION.md \
  evaluation/android_model_audit/PHASE_4_FINAL_READINESS.md \
  evaluation/android_model_audit/PHASE_4_IMPLEMENTATION_REPORT.md \
  evaluation/android_model_audit/PHASE_4_TEST_RESULTS.md \
  evaluation/android_model_audit/PHASE_5_ANDROID_BUILD_REPORT.md \
  evaluation/android_model_audit/PHASE_5_IMPLEMENTATION_REPORT.md \
  evaluation/android_model_audit/PHASE_5_PERFORMANCE_REPORT.md \
  evaluation/android_model_audit/PHASE_5_RELEASE_READINESS.md \
  evaluation/android_model_audit/PHASE_5_SECURITY_REPORT.md \
  evaluation/android_model_audit/PHASE_6_ANDROID_RUNTIME.md \
  evaluation/android_model_audit/PHASE_6_FINAL_READINESS.md \
  evaluation/android_model_audit/PHASE_6_IMPLEMENTATION_REPORT.md \
  evaluation/android_model_audit/PHASE_6_SIGNING_SECURITY.md \
  evaluation/android_model_audit/PHASE_6_SIZE_OPTIMIZATION.md \
  evaluation/android_model_audit/PHASE_7_ANDROID_RUNTIME_REPORT.md \
  evaluation/android_model_audit/PHASE_7_FINAL_READINESS.md \
  evaluation/android_model_audit/PHASE_7_IMPLEMENTATION_REPORT.md \
  evaluation/android_model_audit/PHASE_7_SECURITY_REPORT.md \
  evaluation/android_model_audit/PHASE_7_TFLITE_RUNTIME_REPORT.md \
  evaluation/android_model_audit/PHASE_8_CLASS_MAPPING_ANALYSIS.md \
  evaluation/android_model_audit/PHASE_8_DATASET_INVENTORY.md \
  evaluation/android_model_audit/PHASE_8_DATA_QUALITY_REPORT.md \
  evaluation/android_model_audit/PHASE_8_FINAL_READINESS.md \
  evaluation/android_model_audit/PHASE_8_IMPLEMENTATION_REPORT.md \
  evaluation/android_model_audit/PHASE_8_MODEL_EVALUATION_FEASIBILITY.md \
  evaluation/android_model_audit/PHASE_9_ANNOTATION_GUIDELINES.md \
  evaluation/android_model_audit/PHASE_9_ANNOTATION_SCHEMA.md \
  evaluation/android_model_audit/PHASE_9_DATASET_PROVENANCE.md \
  evaluation/android_model_audit/PHASE_9_DATA_VALIDATION.md \
  evaluation/android_model_audit/PHASE_9_FINAL_READINESS.md \
  evaluation/android_model_audit/PHASE_9_IMPLEMENTATION_REPORT.md \
  evaluation/android_model_audit/PHASE_9_SPLIT_STRATEGY.md \
  evaluation/android_model_audit/PREPROCESSING_ANALYSIS.md \
  evaluation/android_model_audit/PRE_UI_CHANGE_REVIEW.md \
  evaluation/android_model_audit/PRIORITIZED_ACTION_PLAN.md \
  evaluation/android_model_audit/ROBUSTNESS_TESTS.md \
  evaluation/android_model_audit/SUGGESTIONS_PENDING_APPROVAL.md \
  evaluation/android_model_audit/eval_plan_200.json \
  evaluation/android_model_audit/label_validation.json \
  evaluation/android_model_audit/robustness_counts.json \
  evaluation/android_model_audit/schema/annotation_schema.json \
  evaluation/android_model_audit/scripts/assign_splits.py \
  evaluation/android_model_audit/scripts/duplicate_diagnostic.py \
  evaluation/android_model_audit/scripts/evaluate_readiness.py \
  evaluation/android_model_audit/scripts/lock_android_contract.py \
  evaluation/android_model_audit/scripts/plan_eval_manifest.py \
  evaluation/android_model_audit/scripts/spec_decoder_math.py \
  evaluation/android_model_audit/scripts/test_assign_splits.py \
  evaluation/android_model_audit/scripts/test_duplicate_diagnostic.py \
  evaluation/android_model_audit/scripts/test_evaluate_readiness.py \
  evaluation/android_model_audit/scripts/test_exif_orientations.py \
  evaluation/android_model_audit/scripts/test_validate_annotations.py \
  evaluation/android_model_audit/scripts/validate_annotations.py \
  evaluation/android_model_audit/scripts/validate_yolo_dataset.py \
  evaluation/android_model_audit/PUBLISH_STAGING_PLAN.md
```

Omitted from this commit: `evaluation/android_model_audit/backups/`, `__pycache__`, the two held SQL scripts, and both SQL files.

`test_images.py` and `test_single_image.py` only add comments that the Crack/Pothole/Rutting/Uneven-Surface strings are not a proven class map. Class mapping stays UNKNOWN. `METRICS.json` is an audit file with null scores, not a measurement.
