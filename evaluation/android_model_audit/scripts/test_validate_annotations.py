"""Synthetic fixtures only. These files are not ground truth."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from evaluation.android_model_audit.scripts.validate_annotations import validate_document

SCRIPT = Path(__file__).resolve().parent / "validate_annotations.py"


def _doc(**overrides):
    doc = {
        "info": {
            "annotation_schema": "tariqmap-annotations-1",
            "annotation_version": "test-1",
            "provenance": "SYNTHETIC TEST FIXTURE NOT GROUND TRUTH",
        },
        "images": [
            {
                "id": 1,
                "file_name": "synthetic-test-image.jpg",
                "width": 100,
                "height": 80,
                "negative": False,
            }
        ],
        "categories": [
            {"id": 1, "name": "pending-fixture-class", "definition_status": "pending_confirmation"}
        ],
        "annotations": [
            {
                "id": 10,
                "image_id": 1,
                "category_id": 1,
                "bbox": [10, 10, 20, 15],
                "annotator_id": "synthetic-annotator",
                "review_status": "accepted",
                "provenance": "SYNTHETIC TEST FIXTURE NOT GROUND TRUTH",
            }
        ],
    }
    doc.update(overrides)
    return doc


class ValidateAnnotationsTest(unittest.TestCase):
    def test_synthetic_document_passes(self) -> None:
        self.assertEqual(validate_document(_doc()), [])

    def test_flags_bad_boxes_classes_duplicates_and_review(self) -> None:
        doc = _doc()
        doc["images"].append({"id": 1, "file_name": "other.jpg", "width": 10, "height": 10})
        doc["images"].append({"id": 2, "file_name": "empty.jpg", "width": 10, "height": 10})
        doc["annotations"][0]["bbox"] = [90, 70, 30, 20]
        doc["annotations"][0]["category_id"] = 99
        doc["annotations"][0]["review_status"] = "unreviewed"
        doc["annotations"][0]["annotator_id"] = ""
        codes = {item["code"] for item in validate_document(doc)}
        self.assertIn("duplicate_image_id", codes)
        self.assertIn("box_outside_image", codes)
        self.assertIn("invalid_class", codes)
        self.assertIn("unreviewed", codes)
        self.assertIn("missing_provenance", codes)
        self.assertIn("empty_annotation", codes)

    def test_missing_image_is_reported_and_nothing_is_written(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            before = list(root.iterdir())
            findings = validate_document(_doc(), image_root=root)
            self.assertEqual(list(root.iterdir()), before)
        self.assertIn("missing_image", {item["code"] for item in findings})

    def test_cli_rejects_invalid_json_and_does_not_touch_dataset(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bad = root / "synthetic-not-ground-truth.json"
            bad.write_text("{", encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(SCRIPT), "--annotations", str(bad)],
                check=False,
                capture_output=True,
                text=True,
            )
        self.assertEqual(completed.returncode, 2)
        report = json.loads(completed.stdout)
        self.assertEqual(report["findings"][0]["code"], "invalid_json")
        self.assertFalse(Path("/tmp/Road-damage-project/Global_Potholes_Dataset-image/labels").exists())


if __name__ == "__main__":
    unittest.main()
