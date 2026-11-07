# Phase 9 annotation guidelines

These rules are for a future human pass. They do not label the 29,120 JPEGs. Category definitions that the repo does not establish stay **pending confirmation**. Do not map a drawn box to D00, D10, D20, or D40 while that mapping is unproven. Do not copy a model prediction into the file and call it ground truth.

## Supported categories

No damage category is confirmed for this image set.

The app displays D00, D10, D20, and D40. `test_images.py` displays Crack, Pothole, Rutting, and Uneven-Surface in a different index order. `source-class-map.json` puts rutting at D90. An upstream notebook in `oracl4/RoadDamageDetection` (`training/0_PrepareDatasetYOLOv8.ipynb`) writes D00=0, D10=1, D20=2, D40=3 for the CRDDC 2022 conversion that repo describes. That notebook is not a label guideline for these UUID files, and the TFLite bytes were not matched to that project's `.pt`.

Until someone records a written definition and a reviewed example set, annotators use a pending name they were given for that task, with `definition_status: pending_confirmation`. If the instruction for a category is missing, they do not invent one. They mark the region `unclassifiable` only if the task sheet includes that pending name.

## Box rules

- One box is one region. Format is COCO pixels: left, top, width, height.
- The box touches the outermost visible pixels of the region and stays inside the image.
- Do not draw a box that is only a shadow, lane paint, or a vehicle unless the task sheet says that is in scope. Scope is pending, so those cases stay out.
- A confirmed empty image is `images[].negative: true` after review. An image with no boxes and no negative flag is incomplete, not a negative.

## Ambiguous cases

If two pending categories both fit, draw nothing for that region and leave a note in `provenance` that it was ambiguous. Do not pick D-codes to break the tie.

## Occlusion and overlap

Draw the visible extent only. A second damage region that overlaps gets its own box. Do not merge overlapping regions of different pending categories into one box.

## Small regions

If the region is still visibly a damage area at the image's native size, box it. If it is a few pixels and the annotator cannot tell what it is, do not box it. There is no pixel cutoff in the repo evidence, so no numeric minimum is set here.

## Uncertain or unclassifiable

Use review status `unreviewed` until a second person accepts or rejects the box. Rejected boxes stay in the file with `review_status: rejected` so the validator can see them. They are not training labels.

## Quality review

Every accepted box needs `annotator_id`, `provenance`, and `review_status: accepted`. A second person, not the same id, should accept it. The validator fails a file that still has `unreviewed` or `rejected` boxes, missing provenance, boxes outside the frame, unknown category ids, duplicate image ids, or images that are neither boxed nor marked negative.

Status of these guidelines as operating procedure: PARTIALLY VERIFIED as written rules. Status of category definitions: NOT VERIFIED.
