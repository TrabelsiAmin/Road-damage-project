# Phase 11 final acceptance checklist

A Play release is not ready. Every item below is NOT DONE. Host tests that passed this phase do not check these boxes.

Recorded this phase: HEAD `cd7d16898465174c06a1362953c052f156e0485b`. `flutter analyze` clean. `flutter test` 149 passed. Python unittest of the Phase 10 modules plus the 13 tool tests: 49 passed (36 + 13). SQL contract OK. Spec math OK. Dashboard vitest 93 passed. Dashboard production build succeeded. Android rebuilds were not run.

| # | Requirement | Status | Evidence gap |
| --- | --- | --- | --- |
| 1 | ARM64 APK installed and launched | NOT DONE | The APK exists (162,451,078 bytes) and was not installed. `adb devices` is empty. `/dev/kvm` returns EACCES on this Linux host |
| 2 | Critical Android runtime tests | NOT DONE | Camera, gallery, offline queue, retry, and restart have no device or emulator log. The manual protocol rows are NOT EXECUTED |
| 3 | Both TFLite paths on Android | NOT DONE | The existing APK was built without `USE_ROADSENSE_MODEL`. No Android log shows legacy init or the RoadSense-plus-legacy-D40 path |
| 4 | Upload key signs the release AAB | NOT DONE | The AAB (231,089,677 bytes) was signed `CN=Android Debug` in Phase 6/7. No upload keystore was created here |
| 5 | Scientific evaluation with verified ground truth and class mapping | NOT DONE | 29,120 JPEGs, 0 labels, mapping UNKNOWN. `evaluate_readiness.py` is specified to return null metrics. No mAP was calculated |
| 6 | Production Supabase migration and security review, separately approved | NOT DONE | `supabase/migrations/20261105_submit_observation_stable_ids.sql` was applied only to disposable local database `tariqmap_phase4` in Phase 4. It must not be applied to production from this work. No production approval is recorded |

Host regression, static APK inspection, and tensor-shape checks are not items 1 through 6.
