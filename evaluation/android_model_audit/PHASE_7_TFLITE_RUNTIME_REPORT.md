# Phase 7 TFLite runtime report

Neither model was modified. No interpreter was created on Android. A successful host test is not an accuracy result and is not a device init.

## Device / emulator

| Check | Result |
| --- | --- |
| Default model init on device | NOT EXECUTED |
| Input/output shapes from a live interpreter | NOT EXECUTED |
| Stretch to 640×640 on a camera or gallery frame | NOT EXECUTED |
| Decoder on actual model output | NOT EXECUTED |
| RoadSense stays off in the installed APK | NOT EXECUTED (the APK was not installed; it was built without `USE_ROADSENSE_MODEL`) |
| Legacy model still available for D40 on the hybrid path | NOT EXECUTED |
| logcat | NOT EXECUTED |

Status of on-device TFLite: BLOCKED, same KVM / missing emulator reason as the runtime report.

## Host checks that did run

These ran inside `flutter test` (149 passed) and `spec_decoder_math.py` (SPEC MATH OK). Label: automated/host. Not runtime.

| Check | Where | What it shows |
| --- | --- | --- |
| Default asset is `assets/models/road_damage.tflite` and RoadSense is a different file | `model_asset_test.dart` | `useRoadSenseModel` is false. Both on-disk checksums match `ModelConfig` |
| Legacy tensor contract | `legacy_decoder_test.dart` | Measured shape `[1, 8, 8400]` is accepted. The RoadSense shape is rejected by the legacy decoder |
| D40 threshold | same file | 0.38 dropped, 0.41 kept, at the existing 0.40 threshold. Thresholds were not changed |
| `onlyD40` | same file | A stronger crack on another anchor is dropped when the runner is the D40-only path |
| Stretch | `legacy_stretch_contract_test.dart` | `stretchToModelInput` fills 640×640 and does not insert gray-114 bars |
| Decoder math | `evaluation/android_model_audit/scripts/spec_decoder_math.py` | SPEC MATH OK |

Source, not a device log: `DetectionService.create` loads `road_damage` unless `USE_ROADSENSE_MODEL` is true. That flag is `bool.fromEnvironment(..., defaultValue: false)`. When it is true, `_createHybridService` loads `road_damage_roadsense` and, because `USE_POTHOLE_MODEL_FOR_D40` defaults to true, also loads `road_damage` as `road_damage_pothole` with `onlyD40: true`. `TFLiteAgentRunner` checks `[1, 640, 640, 3]` in and `[1, 8, 8400]` out at load. `RoadSenseAgentRunner` checks NCHW `[1, 3, 640, 640]` and `[1, 9, 8400]`. Those checks did not execute inside an APK.

The rebuilt arm64 APK and the AAB each contain both files once, uncompressed, with SHA-256 prefixes `830f99bd8c31c5d2` and `300798be883a7003`. That confirms packaging, not inference.

No regression test was added. No defect was demonstrated.
