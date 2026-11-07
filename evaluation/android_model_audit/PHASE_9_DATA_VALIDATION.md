# Phase 9 data validation

Script: `evaluation/android_model_audit/scripts/validate_annotations.py`.

It reads one JSON file and optionally an image root. It does not create labels, and it refuses `--out` inside `Global_Potholes_Dataset-image`. Tests live in `test_validate_annotations.py` and use documents tagged `SYNTHETIC TEST FIXTURE NOT GROUND TRUTH`.

## Checks

| Finding code | Condition |
| --- | --- |
| `invalid_json` | file is not JSON |
| `invalid_structure` | schema id, arrays, image size, or review value is wrong |
| `missing_provenance` | info version/provenance, annotator id, or annotation provenance is blank |
| `missing_image` | `--images` was set and `file_name` is not there |
| `duplicate_image_id` | repeated image id |
| `duplicate_annotation_id` | repeated annotation id |
| `invalid_class` | `category_id` is not in `categories` |
| `invalid_box` | bbox is not four numbers, or width/height is not positive |
| `box_outside_image` | `x+width` or `y+height` exceeds the image |
| `empty_annotation` | image has no boxes and `negative` is not true |
| `unreviewed` | `review_status` is not `accepted` |

Exit 0 only when the finding list is empty. Exit 2 otherwise.

## Tests

`python3 -m unittest evaluation.android_model_audit.scripts.test_validate_annotations` passed inside the combined 11-test run (3 of those tests). A valid synthetic document produces no findings. A second fixture triggers duplicate image id, box outside the image, invalid class, unreviewed, missing provenance, and empty annotation. Invalid JSON exits 2. The real `labels/` directory was not created.

The 29,120 JPEGs were not validated as a labeled set because they have no annotation file. Status of the checker: VERIFIED on synthetic fixtures. Status of real ground truth: NOT APPLICABLE.
