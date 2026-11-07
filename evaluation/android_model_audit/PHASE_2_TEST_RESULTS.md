# Phase 2 test results

Run on the clone at `/tmp/Road-damage-project`. No test called production Supabase. `training/test_rls.py`, `test_rls.py`, `test_supabase.py`, and `test_sync_simulation.py` were not run.

`flutter` and `dart` are not on this machine. Dart tests were written and are BLOCKED. They are not a pass.

## Passed

| Command | Result | Status |
| --- | --- | --- |
| `python3 training/tests/test_contracts.py` | 2 passed | VERIFIED |
| `python3 evaluation/android_model_audit/scripts/lock_android_contract.py` | `CONTRACT OK` | VERIFIED |
| `python3 evaluation/android_model_audit/scripts/spec_decoder_math.py` | `SPEC MATH OK` | VERIFIED |
| `python3 evaluation/android_model_audit/scripts/test_exif_orientations.py` | 6 passed | PARTIALLY VERIFIED (Pillow oracle and Dart source check; Dart runtime BLOCKED) |
| `python3 backend/test_api_validation.py` | 6 passed | VERIFIED |
| `python3 backend/test_sync_recovery.py` | 11 passed | PARTIALLY VERIFIED (in-memory store; Flutter upload BLOCKED) |
| `npm test` in `dashboard/` | 18 files, 90 tests passed | VERIFIED |
| `npx esbuild src/App.jsx --bundle --packages=external` | `ESBUILD_OK` | VERIFIED as a syntax check only |

The new dashboard tests cover null, blank, D99, and D00–D40; an empty analytics set; and an incomplete set where missing and unknown classes stay out of D40. The sync tests cover a full insert, a repair when the observation already exists, a second call that does not post again, a duplicate child id, a media flag that blocks completion, a stuck `uploading` row returning to `pending`, a failed detection post with no receipt, an auth failure that inserts nothing, an old random child id left in place, blank class stats, and JWT redaction.

## Blocked

| Tests | Why | Status |
| --- | --- | --- |
| `app/test/unit/class_codes_test.dart` | no Dart SDK | BLOCKED |
| `app/test/unit/confidence_threshold_test.dart` | no Dart SDK | BLOCKED |
| `app/test/unit/sync_plan_test.dart` | no Dart SDK | BLOCKED |
| `app/test/unit/exif_orientation_test.dart` | no Dart SDK | BLOCKED |
| `app/test/unit/legacy_decoder_test.dart` | no Dart SDK | BLOCKED |
| `app/test/unit/legacy_stretch_contract_test.dart` | no Dart SDK | BLOCKED |
| Widget and integration tests under `app/test/` | no Flutter SDK | BLOCKED |

The confidence slider was not given a Python stand-in. The Dart file is the test, and it did not run.

## Not run, on purpose

- Live Supabase health, RLS, or sync scripts.
- Any SQL migration.
- Device inference, adb, or a Flutter drive.
- A browser click-through of the dashboard. esbuild and vitest do not open the case dialog.

## Notes

- FastAPI printed `StarletteDeprecationWarning` about httpx. The 6 validation tests still passed.
- The EXIF pixel checks allow JPEG rounding (a red of 254 still counts as red). They check orientation 1, 3, 6, and 8 geometry, a missing tag, a tag of 99, and that `preprocessing.dart` still stretches with `copyResize` and bakes only in the two orientation helpers.
- No test was weakened. `lock_android_contract.py` still requires the D20 0.30 and D40 0.40 literals and the stretch call.
