# Phase 3 decisions still needing you

Phase 2 items that this phase did not reopen stay open. The model is still not scientifically validated.

## Needs a decision before production

1. Apply `supabase/migrations/20261105_submit_observation_stable_ids.sql` on staging, then through the normal migration path. It is not applied. It replaces `submit_observation` in place. Current Flutter always sends UUID v5 child ids. Another client that omits those ids will get an error instead of a random id. That is the intended fail-closed change. Confirm it before applying.
2. Leave old random-id children. This phase does not delete or merge them. A cleanup is a separate migration and needs a reviewed duplicate report. The diagnostic script is local and was not run on production.
3. Do not add a unique index on `locations` in that migration. Existing duplicate location rows could make the migration fail. Add one only after a staging check.
4. Recommended RLS and storage text in `supabase/recommended/rls_and_storage_NOT_APPLIED.sql` is comments. Applying an authenticated-only insert policy will stop the current anon ingest unless the app's insert path is authenticated first. Env vars do not make the current policies safe.
5. Unknown class codes still cannot pass the SQL check, which allows only D00, D10, D20, and D40. They stay on the device if the RPC raises. Widening that check would be a product and schema decision. This phase did not rename classes or invent a mapping.
6. `app/pubspec.lock` moved six transitive packages (`characters` 1.4.0 to 1.4.1, `matcher` 0.12.17 to 0.12.20, `material_color_utilities` 0.11.1 to 0.13.0, `meta` 1.17.0 to 1.19.0, `test_api` 0.7.7 to 0.7.12, `vector_math` 2.2.0 to 2.4.4) and records Dart `>=3.11.0-0` because `flutter pub get` ran under Flutter 3.47.9. `pubspec.yaml` was not edited. Revert the lock if the team needs the previous pins. The Dart results in `PHASE_3_TEST_RESULTS.md` used the new lock.
7. The 13 Flutter failures need the missing golden images. They were not fabricated. RoadSense letterbox goldens are not a reason to change the default Android stretch path.

## Still open from Phase 2

1. Letterbox. Stretch remains the Android path for `road_damage.tflite`.
2. Class names. D00, D10, D20, and D40 stay. Display for anything else is `Unknown class`.
3. Retrain and weight replacement. Not done.
4. Labeled evaluation and mAP. Not computed. `validation_metrics.json` is not shown.
5. Phone benchmark. This machine has no Android SDK, adb, or emulator. Host timings are not phone timings.
6. Remove the public anon literal from debug and from `flutter run`. Production Vite no longer includes it. Debug still does, so local startup works. Removing it needs every build to inject the public key.
7. iOS. `ios/` was not edited.
8. A saved slider replaces all four class floors. That is implemented and unit-tested. Reverse it if a saved score should not be global. NMS IoU stays 0.45 either way. Range stays 0.10–0.80.

## Already chosen, so you can reverse them

- Client observation ids are kept. Agent-run, detection, and media ids are UUID v5 from the local observation id. Retries reuse them.
- Receipts are written after the required rows. Incomplete media does not mark the local row synced.
- Pending and failed rows stop at `maxRetries` (default 5) and become `needsReview`. Local rows are not deleted.
- Dashboard pages are 500 rows, merged by id, with a truncation banner. Missing times are not treated as now. Unknown is not D40. Empty rates stay empty.
- The duplicate tool only reports. `deleted` and `merged` stay 0.

## Status

| Item | Status |
| --- | --- |
| Staging apply of the new SQL | NOT VERIFIED. File only |
| RLS and storage recommendations | NOT VERIFIED. Not executed |
| Production duplicate report | NOT VERIFIED |
| Lockfile transitive bump | PARTIALLY VERIFIED. Tests ran on it. Revert is open |
| APK, emulator, device EXIF, phone timings | BLOCKED. No Android SDK |
| Letterbox, rename, retrain, labeled mAP, iOS | NOT APPLICABLE this pass |
