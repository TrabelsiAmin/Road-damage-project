# Phase 8 data quality

Read-only. No image or label was modified or deleted. No blob download was completed. A `git cat-file` that started a lazy fetch of missing blobs was stopped. Git gc that had already started was left to finish.

## Counts

| Fact | Value | Status |
| --- | --- | --- |
| Index JPEGs under `Global_Potholes_Dataset-image` | 29,120 `.jpg`, 0 other files | VERIFIED (`git ls-files`) |
| Working-tree JPEGs there | 200 | VERIFIED (`Path.iterdir`) |
| Other on-disk images | 9 `inference_results` JPEG, 6 golden JPEG, app icons PNG | VERIFIED, not the dataset |
| Annotation files | 0 YOLO txt, 0 COCO json, 0 VOC xml, 0 csv | VERIFIED in the git index |
| Labeled images | 0 | VERIFIED |
| Unlabeled images | 29,120 of the index set | VERIFIED |
| Class distribution | not computed | NOT APPLICABLE. No labels |
| Malformed boxes / invalid class indices | not computed | NOT APPLICABLE. No labels |

The earlier "about 29,120 JPEGs and 0 labels" statement matches this recount exactly: 29,120 and 0.

## Decode

Method: for each checked-out dataset JPEG, read the file and parse JPEG markers through SOS, requiring SOI and an SOF0/SOF1/SOF2 size. This is a header parse, not a pixel decode.

| Item | Result |
| --- | --- |
| Opened | 200 |
| Unreadable | 0 |
| Skipped | 28,920 |
| Why skipped | Sparse checkout excludes them and the clone filter is `blob:none`, so the bytes are not local. A full fetch was not run. |
| Distinct sizes among the 200 | 24 |
| Most common | 640×480 (77), 640×360 (62), 640×486 (16) |

Status: PARTIALLY VERIFIED. The 200 that exist locally parsed. The other 28,920 were not opened. Near-duplicate perceptual hashing was not done.

## Exact duplicates

Method: `git ls-files -s` blob ids. Git hashes file bytes, so equal ids are equal bytes. This does not need the blob bodies. It covers all 29,120 index paths.

| Item | Result |
| --- | --- |
| Unique blobs | 29,028 |
| Duplicate groups | 92 |
| Largest group | 2 |
| Extra copies | 92 |

Example pairs:

- `008ecb2c-d3b3-4e7e-96b3-4f5b95a1e516.jpg` and `3441bc05-f3a2-4388-9735-eafbad412da3.jpg`
- `036406dc-6f1d-4157-bf5c-72d87e7ae88e.jpg` and `ce3490ca-71f1-4eac-89f8-6fab441afe84.jpg`
- `03b78b50-9a7b-49a0-be87-250f45ab6c4b.jpg` and `4c9def82-30b5-49bb-bab9-c8e054544fea.jpg`

The September audit's "0 duplicates in a sample of 200" is a sample. It does not conflict with 92 exact pairs in the full index. Status of exact duplicates: VERIFIED. Status of near-duplicates: NOT EXECUTED.

## Splits and leakage

`git ls-files` has no `images/train`, `images/val`, `images/test`, or `labels/` paths. `training/data/` is absent. The YAML files under `training/config/` point at `data/processed/{cracks,pavement,surface}`, which are not in the tree. Leakage cannot be measured. Status: VERIFIED that no split exists. Leakage: NOT APPLICABLE.

## What was not done

- Pixel decode or checksum of the 28,920 absent blobs.
- Perceptual hashes.
- Any rewrite, deletion, or sparse-checkout change.
