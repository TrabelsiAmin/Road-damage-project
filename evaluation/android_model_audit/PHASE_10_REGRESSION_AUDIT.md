# Phase 10 regression audit

Read of the current tree. No product behavior was changed. Two tests were added so tooling checks that the code already implemented are locked. No refactor.

## Contracts that still match the code

| Contract | Where | Result |
| --- | --- | --- |
| Default model `road_damage.tflite`, RoadSense only with `USE_ROADSENSE_MODEL`, hybrid path also loads the legacy file for D40 | `detection_service.dart`, `constants.dart` | Present. Not changed |
| Stretch to 640×640, not letterbox, for the legacy runner | `preprocessing.dart`, `legacy_stretch_contract_test.dart` | Present |
| EXIF orientation before that stretch | `preprocessing.dart`, `exif_orientation_test.dart` | Present |
| Output `[1, 8, 8400]` legacy and `[1, 9, 8400]` RoadSense | runners and `spec_decoder_math.py` | Present |
| Defaults D00/D10 0.35, D20 0.30, D40 0.40 | `confidence_threshold.dart`, `tflite_agent_runner.dart` | Present |
| Slider 0.10–0.80 replaces every class floor only after save | `activeThresholds` | Present |
| NMS IoU 0.45 is not the slider | `nmsIouThreshold` | Present |
| Unknown codes stay `Unknown class` and are not rewritten to D40 | `class_codes.dart` | Present |
| Offline queue and stuck-upload recovery | `observation_repository.dart`, `sync_plan.dart`, backend recovery tests | Present |
| UUID v5 from the observation id for runs, detections, and receipts | `backend/supabase_store.py` | Present |
| Dashboard does not render `validation_metrics.json` | `metricsHonesty.test.js` | Present |
| Flutter and dashboard clients reject a service-role JWT | `supabase_config.dart`, `dashboard/src/supabase.js` | Present |
| Anon literal is used only when `kDebugMode` is true | `SupabaseCfg.anonKey` | Present. Release without a dart-define returns an empty key and `assertPublicConfig` fails |
| Release signing uses the upload key only when all four values are set | `app/android/app/build.gradle.kts` | Present. Otherwise the debug config |

`training/config/augmentation.yaml` still lists D20 0.28 and D40 0.42. The app does not load that file. The runner comment says so. That is a documented difference, not a second runtime path.

`test_images.py` still lists Crack, Pothole, Rutting, Uneven-Surface and says that list is not the Android contract. It was not treated as a mapping.

## Defects

No product defect was demonstrated in this pass. Interpreter lifecycle (`close` on dispose), camera `enableAudio: false`, and the inactive/resume camera path were not executed on a device, so they were not patched.

Android runtime remains unverified. This phase opened `/dev/kvm` and got `EACCES` (errno 13). `adb devices` listed nothing. No APK was installed. Android builds were not rerun because Android sources were not edited.

## Host regression

| Suite | Result |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter test` | 149 passed |
| Python contracts, API, sync, offline, SQL contract, EXIF | 36 passed |
| `lock_android_contract.py` | CONTRACT OK |
| `spec_decoder_math.py` | SPEC MATH OK |
| Annotation and split tools | 13 passed (Phase 9 had 11; two tests were added) |
| Dashboard vitest | 93 passed |
| Dashboard `npm run build` | built |
| Android debug, release, AAB | NOT EXECUTED |

No assertion was weakened. No suite failed.
