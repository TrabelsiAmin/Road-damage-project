# Phase 8 final readiness

Scientific validation did not become true in this phase. The app build status from Phase 7 is unchanged because Android was not rebuilt and was not edited.

## Status

| Question | Status |
| --- | --- |
| Dataset image count | VERIFIED. 29,120 JPEG paths in git. 200 checked out. 0 other files in that directory. |
| Ground truth | VERIFIED absent. 0 annotation files. |
| Exact duplicate pairs | VERIFIED. 92 pairs, 29,028 unique blobs. |
| Corruption of every JPEG | PARTIALLY VERIFIED. 200 local headers parsed, 0 failures. 28,920 not opened. |
| Class mapping | NOT VERIFIED. UNKNOWN. Not proposed. |
| Metrics | NOT APPLICABLE. Not calculated. |
| Evaluation script | VERIFIED as a refusal gate. It does not score. |
| Host regression | VERIFIED. Analyze clean, Flutter 149, Python 36, contract OK, spec math OK, vitest 93, vite build OK. New gate tests 3 passed. |
| Android rebuild | NOT EXECUTED. No Android edit. |
| Play upload | Still blocked by the Phase 7 items: debug-signed AAB, no device run. |
| Production Supabase | NOT APPLICABLE. Not contacted. |

## Assumptions that were not used as facts

- README "RDD2022 4-class" wording.
- `docs/dataset-audit.md` instance counts.
- `dashboard/src/data/validation_metrics.json` numbers.
- Either class-index list being the true channel order.

## Remaining requirements

Labeled boxes, a mapping proven from the training export or from those labels, a leakage-safe split that keeps the 92 duplicate pairs together, and then inference with the current stretch decoder. Scores come after that, not before. Both TFLite files stay in the app. RoadSense stays off unless `USE_ROADSENSE_MODEL` is set.

## Git

HEAD `cd7d16898465174c06a1362953c052f156e0485b`. Not committed. Not pushed.

Tracked diff against HEAD is still the Phase 1–7 tree (51 files, +2085 / −996). Phase 8 added untracked scripts under `evaluation/android_model_audit/scripts/` and these reports. Model SHA-256 values are unchanged. No dataset file was deleted. `ios/` was not edited.
