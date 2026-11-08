# Dataset audit

## Full git tree — VERIFIED

`git ls-tree -r --name-only HEAD Global_Potholes_Dataset-image` returns **29,120** paths, all ending in `.jpg`. No `.txt`, `.xml`, `.json`, or `.csv` beside them.

`training/reports/global_potholes_audit.json` (2026-09-19): `image_count` 29120, `annotation_status` **UNLABELED**, `train_val_test_split` NOT_PRESENT, verdict STOP. The image count matches the tree. Dimension scan in that file was skipped. Duplicate claim there (0 of an unspecified 200) was **not** repeated as a full-set measurement.

`docs/dataset-audit.md` lists D00 1,245, D10 890, D20 3,450, D40 12,055 and 45 missing labels. Those counts are **NOT VERIFIED** and contradict the JSON audit and the file tree.

## This working tree — PARTIALLY VERIFIED

The clone used for this phase is sparse. `find` sees **200** jpeg files on disk, not 29,120. `validate_yolo_dataset.py` against `Global_Potholes_Dataset-image/labels` wrote `label_validation.json`:

- status **BLOCKED**
- image_count 200 (checked-out files only)
- label_file_count 0
- reason: labels directory does not exist

Do not quote 200 as the dataset size. The dataset size is 29,120 images in git.

## Sample from the previous phase

A 200-image Pillow sample (seeds 42 and 7) had 0 corrupt files and 0 SHA-256 duplicates inside the sample. Common sizes 640×480 (77) and 640×360 (62). That is a sample, not the population. Tag: **VERIFIED** for those 200 files only.

## Eval plan — NOT a labeled set

`scripts/plan_eval_manifest.py --names-file` (the 29,120 git paths) wrote `eval_plan_200.json`.

- seed `20261105`
- listed 200 names
- hash buckets: train 138, val 29, test 33
- status `PLAN_ONLY`

No image was copied, moved, or deleted. No box was written. The word “train” in the manifest is a split name for a future labeled study. This audit forbids training on it. mAP on this plan is **NOT APPLICABLE** until a person adds YOLO labels in a separate directory and the validator returns VERIFIED.
