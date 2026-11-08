# Phase 2 decisions still needing you

These were not done. Phase 1 suggestions that this phase did not reopen stay open.

## Needs a decision

1. Letterbox. Stretch is still the Android path. One unlabeled image is not a reason to switch. Changing it needs the original export settings and a labeled check.
2. Class names. D00, D10, D20, and D40 stay. The plain-language strings already in the app are marked unconfirmed. A new name needs model metadata or a labeled map. Do not invent one.
3. Retrain and weight replacement. Not done. There is no `.pt` in the tree and the image set is unlabeled.
4. Labeled evaluation. mAP is still unknown. `validation_metrics.json` is not shown. A human-labeled set is required before any accuracy number.
5. Phone benchmark. This machine has no Flutter, adb, or emulator. Linux timings from earlier notes are not phone timings.
6. Production RLS and Storage. Recommended text is in `PHASE_2_SECURITY_REVIEW.md`. No SQL was run.
7. Remove the anon literal. Env and `--dart-define` now override it. The literal remains so local startup works. Removing it is safe only after every build injects the same public key.
8. iOS. `ios/` was not edited.
9. Saved global slider versus per-class floors. The slider applies only after the user saves. Until then, D00/D10 stay 0.35, D20 stays 0.30, and D40 stays 0.40. NMS IoU stays 0.45. Confirm that a single saved score should replace all four floors. The defaults were not taken from a test metric.
10. `submit_observation` ids. The client and the Python store use UUID v5. If the SQL function inserts different ids, a retry can duplicate children. Confirm the function, on staging, before relying on repair in production.
11. Old random child rows. Repair does not delete them. A cleanup would be a migration and was not written.

## Already chosen in this pass, so you can reverse them

- Unknown and missing classes display `Unknown class` and are excluded from D00/D10/D20/D40 counts. They are not rewritten in the database.
- A repaired sync returns `status: "repaired"` with the same `{status, id}` body. Callers that only read `id` are unchanged. The dashboard does not call this FastAPI route.
- Empty dashboard rates stay null. Unknown classes add no catalogue cost. A missing export priority is blank rather than 50.

## Status

| Item | Status |
| --- | --- |
| Letterbox, rename, retrain, labeled mAP, device benchmark, production SQL, iOS | NOT APPLICABLE this pass |
| Anon literal removal | NOT VERIFIED; fallback kept |
| Slider runtime | BLOCKED (no Dart SDK) |
| Flutter EXIF, class handler, and sync client | BLOCKED (no Dart SDK) |
| Dashboard class and empty-data tests | VERIFIED |
| In-memory sync planner | VERIFIED |
| RLS recommendations | NOT VERIFIED; not executed |
