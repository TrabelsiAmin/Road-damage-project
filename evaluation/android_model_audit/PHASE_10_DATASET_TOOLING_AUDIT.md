# Phase 10 dataset and tooling audit

## Dataset

Recomputed this phase without downloading blobs.

| Check | Result | Status |
| --- | --- | --- |
| Git index under `Global_Potholes_Dataset-image` | 29,120 `.jpg`, 0 other extensions | VERIFIED |
| Working tree files there | 200 | VERIFIED. This is the sparse checkout, not the dataset |
| Unique blob ids | 29,028 | VERIFIED |
| Duplicate groups | 92, each an extra copy of 1 | VERIFIED |
| `git diff` on that directory and on `app/assets/models` | empty | VERIFIED |
| JSON or TXT written next to the real JPEGs | none. No `labels/` directory | VERIFIED |
| TFLite SHA-256 | unchanged from Phase 6 | VERIFIED |

## Tooling checks

All ten checks were run through `python3 -m unittest` on the three tool modules. 13 tests passed.

| # | Check | Evidence | Status |
| --- | --- | --- | --- |
| 1 | Invalid annotations rejected | Bad boxes, duplicate ids, blank provenance, invalid JSON exit 2 | VERIFIED |
| 2 | Unknown classes are not silently mapped | `category_id` 99 produces `invalid_class` and is not rewritten | VERIFIED |
| 3 | Duplicate groups cannot cross splits | Ids `a` and `b` with one hash land in one split | VERIFIED |
| 4 | Seeds are reproducible | Seed 7 returns the same assignment twice | VERIFIED |
| 5 | Missing images are reported | New test: `missing_image` when the image root does not contain the file, and the temp directory is unchanged | VERIFIED |
| 6 | Real files are not overwritten or deleted | Validator refuses `--out` inside `Global_Potholes_Dataset-image`. Split CLI exits 2 on that path. Dataset diff is empty | VERIFIED |
| 7 | Synthetic fixtures are separated | Fixture strings say `SYNTHETIC TEST FIXTURE NOT GROUND TRUTH` or `synthetic-`. They are not under the image directory | VERIFIED |
| 8 | Missing ground truth keeps metrics null | Repo dataset and an empty temp dir | VERIFIED |
| 9 | Missing class mapping stays blocked | Exit 2, `NOT EVALUABLE`, `mapping_verified` false | VERIFIED |
| 10 | A candidate schema is not verified ground truth | Synthetic COCO is counted as a candidate. With or without a `VERIFIED` mapping file, `metrics` stays null and the status stays `NOT EVALUABLE` | VERIFIED |

The new tests are `test_missing_image_is_reported_and_nothing_is_written` and `test_confirmed_candidate_with_verified_mapping_still_has_null_metrics`. They did not replace the Phase 9 assertions.

No metric was calculated. Class mapping was not marked proven. Evaluation remains blocked.
