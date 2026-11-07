# Phase 9 split strategy

Script: `evaluation/android_model_audit/scripts/assign_splits.py`. Tests: `test_assign_splits.py`.

No split of the 29,120 images was created. The CLI exits 2 if the records path contains `Global_Potholes_Dataset-image`.

## Rule

Input records are `{id, content_hash}`. Records with the same hash are one group. The group is placed by SHA-256 of `seed|hash`:

- unit &lt; 0.70 → train
- unit &lt; 0.85 → val
- otherwise → test

The same seed and the same records always return the same JSON. A group is never divided. Original images and annotation files are not read or written.

`class_distribution` returns null unless the caller passes `verified=True`. The CLI always emits `class_distribution: null`. The 92 real duplicate pairs were not assigned to train or test.

## Tests

Synthetic ids `a` and `b` share a hash and land in one split. Seed 7 repeats. Unverified records do not produce class counts. A synthetic JSON file of two ids returns `group_count: 1`. The real dataset path is refused.

Status: VERIFIED for the synthetic tests. A scientific split of the image set: NOT APPLICABLE until accepted labels exist. When that happens, build groups from `content_sha256` (the 92 known duplicate blob ids must stay together) and only then call `class_distribution` with `verified=True`.
