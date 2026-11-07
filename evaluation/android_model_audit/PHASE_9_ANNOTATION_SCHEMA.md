# Phase 9 annotation schema

Schema file: `evaluation/android_model_audit/schema/annotation_schema.json` (`$id` `tariqmap-annotations-1`). It has no image ids and no boxes for the real JPEGs.

The document is COCO JSON plus a few fields COCO does not define. Boxes are COCO absolute pixels: `[x, y, width, height]` from the top-left. A future evaluator can validate them with `validate_annotations.py`.

## Fields

| Field | Where | Required |
| --- | --- | --- |
| `info.annotation_schema` | const `tariqmap-annotations-1` | yes |
| `info.annotation_version` | string | yes |
| `info.provenance` | where this file came from | yes |
| `images[].id` | integer image id | yes, unique |
| `images[].file_name` | path relative to the image root | yes |
| `images[].width`, `images[].height` | positive pixels | yes |
| `images[].content_sha256` | optional content hash for duplicate grouping | no |
| `images[].negative` | true only when a reviewer confirms there is no box | no |
| `annotations[].id` | integer | yes, unique |
| `annotations[].image_id` | must match an image | yes |
| `annotations[].category_id` | must match `categories[].id` | yes |
| `annotations[].bbox` | four numbers inside the image | yes |
| `annotations[].annotator_id` | who drew the box | yes |
| `annotations[].review_status` | `unreviewed`, `accepted`, or `rejected` | yes |
| `annotations[].provenance` | human, tool, or import note | yes |
| `categories[].name` | label string | yes |
| `categories[].definition_status` | `pending_confirmation` or `confirmed` | yes |

## Categories

Do not use D00, D10, D20, or D40 as category names in a real file until a mapping is evidenced. The schema allows any non-empty name. New real files should use `definition_status: pending_confirmation`. Model predictions are not a provenance value that counts as ground truth.

`evaluate_readiness.py` recognizes `info.annotation_schema == tariqmap-annotations-1` as a candidate input via `--annotations`. It still returns `metrics: null` and `NOT EVALUABLE` until `mapping_status` is `VERIFIED` with evidence, and while any category is not `confirmed`.

Status of the schema as a format: VERIFIED (the file parses and the tests use it). Status of any real labels: NOT APPLICABLE. None were written.
