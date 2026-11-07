# Phase 10 working-tree inventory

HEAD `cd7d16898465174c06a1362953c052f156e0485b`. `git status --short` is **51 modified** and **26 untracked** (77 lines). That matches the Phase 9 count. Nothing in this phase was committed. Phase 10 added tests under the already-untracked `evaluation/` tree and these reports. It did not delete or overwrite a Phase 1–9 report.

`git status` does not expand `evaluation/` or `supabase/recommended/`. The full status lines are below. Files inside those directories are grouped after that.

No secret values are copied here.

## Modified tracked files (51)

| Path | Kind | Phase | Purpose |
| --- | --- | --- | --- |
| `app/.gitignore` | configuration | 6 | Ignore `key.properties` and keystores |
| `app/android/settings.gradle.kts` | configuration | 6 | Kotlin 2.3.20 |
| `app/android/gradle.properties` | configuration | 5 | JVM target flag removed in Phase 5 |
| `app/android/app/build.gradle.kts` | configuration | 5–6 | JVM 17 for plugins, minify off, env signing |
| `app/android/app/src/main/AndroidManifest.xml` | configuration | 5 | Backup off, cleartext off, microphone removed |
| `app/pubspec.yaml` | configuration | 6 | Dropped the redundant second model asset line |
| `app/pubspec.lock` | configuration | 3 | Transitive lockfile bump. Dependencies were not upgraded in Phase 10 |
| `app/lib/core/supabase_config.dart` | source | 2–5 | Public URL override, debug-only anon fallback, service-role refusal |
| `app/lib/data/remote/api_client.dart` | source | 2–3 | Sync client and stable ids |
| `app/lib/data/remote/supabase_service.dart` | source | 2 | Client calls |
| `app/lib/inference/preprocessing.dart` | source | 2–4 | EXIF orientation and stretch-to-640 |
| `app/lib/inference/annotation_renderer.dart` | source | 2–4 | Draws known codes; unknown stays `Unknown class` |
| `app/lib/services/tflite_agent_runner.dart` | source | 2–3 | Legacy runner, thresholds, NMS IoU 0.45 |
| `app/lib/services/frame_annotator.dart` | source | 4 | Uses the unknown-class label |
| `app/lib/services/image_compressor.dart` | source | 4 | EXIF-aware compress |
| `app/lib/services/observation_repository.dart` | source | 2–3 | Local save and stuck-upload recovery |
| `app/lib/main.dart` | source | 3 | Public-config assert at startup |
| `app/lib/models/upcoming_anomaly.dart` | source | 2 | D40 only when the code is D40 |
| `app/lib/screens/camera_detection_screen.dart` | source | 2–3 | Capture, EXIF, local save |
| `app/lib/screens/drive_awareness_screen.dart` | source | 4 | Unknown-class display |
| `app/lib/screens/home_screen.dart` | source | 2–3 | Gallery and sync entry |
| `app/lib/screens/model_status_screen.dart` | source | 2–4 | Active model and threshold text |
| `app/lib/screens/offline_queue_screen.dart` | source | 2–3 | Queue and retry |
| `app/lib/screens/result_screen.dart` | source | 2–4 | Result copy for unknown codes |
| `app/lib/screens/settings_screen.dart` | source | 3 | Slider save, IoU stays separate |
| `app/lib/widgets/annotated_image.dart` | source | 4 | Unknown-class overlay |
| `app/lib/widgets/dashboard_map.dart` | source | 2–4 | Map legend includes Other / Unknown |
| `app/test/unit/nms_test.dart` | test | 3–4 | NMS cases |
| `app/test/unit/observation_test.dart` | test | 3–4 | Scores and class agent |
| `app/test/unit/organization_test.dart` | test | 4 | Small expectation update |
| `backend/.env.example` | configuration | 3 | Placeholder env names |
| `backend/main.py` | source | 2–3 | Validation endpoints |
| `backend/schemas.py` | source | 3 | Request bounds |
| `backend/supabase_store.py` | source | 2–3 | UUID v5 ids and partial-write recovery |
| `dashboard/.env.example` | configuration | 3 | Placeholder env names |
| `dashboard/src/App.jsx` | source | 3 | Empty states, no fabricated mAP |
| `dashboard/src/components/ActionCenterView.jsx` | source | 3 | Queue copy |
| `dashboard/src/components/CaseDetailModal.jsx` | source | 3 | Case detail |
| `dashboard/src/components/DataQualityView.jsx` | source | 3 | Removed displayed mAP rows |
| `dashboard/src/components/RoadSegmentRiskView.jsx` | source | 3 | Risk view |
| `dashboard/src/components/layout/Topbar.jsx` | source | 3 | Chrome |
| `dashboard/src/index.css` | source | 3 | Layout |
| `dashboard/src/supabase.js` | source | 3 | Anon client, service-role refusal |
| `dashboard/src/utils/clustering.js` | source | 3 | Cluster counts |
| `dashboard/src/utils/commandCenterAnalytics.js` | source | 3 | Analytics without invented accuracy |
| `dashboard/src/utils/commandCenterAnalytics.test.js` | test | 3 | Analytics tests |
| `dashboard/src/utils/exportFormats.js` | source | 3 | Exports |
| `dashboard/src/utils/ministryAnalytics.js` | source | 3 | Ministry metrics |
| `dashboard/src/utils/roadSegmentRisk.js` | source | 3 | Segment risk |
| `test_images.py` | source | 3 | Class-name comment: list is unproven |
| `test_single_image.py` | source | 3 | Same comment |

Several of these were edited in more than one phase. The phase column is the phase whose report describes the current behavior, not a claim that earlier phases left the file untouched.

## Untracked status lines (26)

```
?? app/android/key.properties.example
?? app/dart_defines.example.json
?? app/lib/core/class_codes.dart
?? app/lib/inference/confidence_threshold.dart
?? app/lib/inference/legacy_decoder.dart
?? app/lib/services/sync_plan.dart
?? app/test/unit/class_codes_test.dart
?? app/test/unit/confidence_threshold_test.dart
?? app/test/unit/exif_orientation_test.dart
?? app/test/unit/legacy_decoder_test.dart
?? app/test/unit/legacy_stretch_contract_test.dart
?? app/test/unit/model_asset_test.dart
?? app/test/unit/sync_plan_test.dart
?? backend/test_api_validation.py
?? backend/test_offline_recovery.py
?? backend/test_sync_recovery.py
?? dashboard/src/supabaseConfig.test.js
?? dashboard/src/utils/analyticsConsistency.test.js
?? dashboard/src/utils/classCodes.js
?? dashboard/src/utils/classCodes.test.js
?? dashboard/src/utils/metricsHonesty.test.js
?? dashboard/src/utils/records.js
?? dashboard/src/utils/records.test.js
?? evaluation/
?? supabase/migrations/20261105_submit_observation_stable_ids.sql
?? supabase/recommended/
```

| Group | Kind | Phase | Purpose |
| --- | --- | --- | --- |
| `class_codes.dart`, `confidence_threshold.dart`, `legacy_decoder.dart`, `sync_plan.dart` and their tests | source, test | 3 | Unknown-class label, slider contract, decoder, sync plan |
| `exif_orientation_test.dart`, `legacy_stretch_contract_test.dart` | test | 3–4 | EXIF and stretch |
| `model_asset_test.dart`, `key.properties.example` | test, configuration | 6 | Default model file and empty signing placeholders |
| `dart_defines.example.json` | configuration | 3 | Placeholder defines, not a filled secret |
| Backend `test_*.py` | test | 3–4 | API, offline, and sync recovery |
| Dashboard `classCodes`, `records`, `metricsHonesty`, `analyticsConsistency`, `supabaseConfig` | source, test | 3 | Honest metrics and anon-key checks |
| `supabase/migrations/20261105_submit_observation_stable_ids.sql` | configuration | 4 | Local contract only. Not applied to production |
| `supabase/recommended/rls_and_storage_NOT_APPLIED.sql` | configuration | 3 | Comments only. Not applied |
| `evaluation/` | reports, tests, backups, generated bytecode | 1–10 | Audit tree. See below |

## Inside `evaluation/`

| Group | Kind | Phase |
| --- | --- | --- |
| `ACCURACY_EVALUATION.md`, `CLASS_MAPPING.md`, `DATASET_AUDIT.md`, `MODEL_ARCHITECTURE.md`, `PREPROCESSING_ANALYSIS.md`, `EXECUTIVE_SUMMARY.md`, `IMPLEMENTATION_REPORT.md`, `METRICS.json`, `METRICS.csv`, `label_validation.json` | report | 1 |
| `PHASE_2_*.md`, `backups/phase2/` | report, backup | 2 |
| `PHASE_3_*.md`, `backups/phase3/` | report, backup | 3 |
| `PHASE_4_*.md`, `backups/phase4/` | report, backup | 4 |
| `PHASE_5_*.md`, `backups/phase5/` | report, backup | 5 |
| `PHASE_6_*.md`, `backups/phase6/` | report, backup | 6 |
| `PHASE_7_*.md` | report | 7 |
| `PHASE_8_*.md`, `scripts/evaluate_readiness.py`, `scripts/test_evaluate_readiness.py` | report, test | 8, tests extended in 9 and 10 |
| `PHASE_9_*.md`, `schema/annotation_schema.json`, `scripts/validate_annotations.py`, `scripts/assign_splits.py` and their tests | report, test | 9, tests extended in 10 |
| `scripts/spec_decoder_math.py`, `lock_android_contract.py`, `validate_yolo_dataset.py`, `test_sql_id_contract.py`, `test_exif_orientations.py`, `duplicate_diagnostic.py` | test | 1–4 |
| `scripts/__pycache__/*.pyc` | generated artifact | test runs | Bytecode. Not source. Not deleted in this phase |
| `PHASE_10_*.md` | report | 10 |

Early audit reports were not overwritten by Phases 6–10. Later phases added new filenames.

## Unexpected changes

None that lack a phase report. The `__pycache__` files are the only generated artifacts mixed into the audit tree. They are not dataset files and they are not secrets.

`Global_Potholes_Dataset-image` and `app/assets/models/*.tflite` have no status lines. `ios/` has no status lines.
