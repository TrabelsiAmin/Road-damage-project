"""The evaluation gate must not emit scores without labels and a verified map."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "evaluate_readiness.py"
REPO = Path(__file__).resolve().parents[3]
MODEL = REPO / "app/assets/models/road_damage.tflite"


class EvaluateReadinessTest(unittest.TestCase):
    def test_repo_dataset_is_not_evaluable_and_has_no_metrics(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(SCRIPT), "--model", str(MODEL)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["status"], "NOT EVALUABLE")
        self.assertIsNone(report["metrics"])
        self.assertEqual(report["labels"]["label_files"], 0)
        self.assertFalse(report["mapping_verified"])
        blob = completed.stdout.lower()
        for banned in ("map50", "map@0.5", "precision", "recall", "f1"):
            self.assertNotIn(banned, blob)
        shapes = report["tensor_shapes"]
        if shapes.get("loaded"):
            self.assertEqual(shapes["input_shape"], [1, 640, 640, 3])
            self.assertEqual(shapes["output_shape"], [1, 8, 8400])

    def test_verified_flag_without_labels_still_refuses(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            mapping = root / "mapping.json"
            mapping.write_text(
                json.dumps({"mapping_status": "VERIFIED", "evidence": ["unit-test fixture only"]}),
                encoding="utf-8",
            )
            (root / "images").mkdir()
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--model",
                    str(MODEL),
                    "--dataset",
                    str(root),
                    "--mapping",
                    str(mapping),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
        report = json.loads(completed.stdout)
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(report["status"], "NOT EVALUABLE")
        self.assertIsNone(report["metrics"])
        self.assertTrue(report["mapping_verified"])
        self.assertEqual(report["labels"]["label_files"], 0)

    def test_labels_without_verified_mapping_still_refuse(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "labels").mkdir()
            (root / "labels" / "a.txt").write_text("0 0.5 0.5 0.2 0.2\n", encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(SCRIPT), "--model", str(MODEL), "--dataset", str(root)],
                check=False,
                capture_output=True,
                text=True,
            )
        report = json.loads(completed.stdout)
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(report["status"], "NOT EVALUABLE")
        self.assertIsNone(report["metrics"])
        self.assertEqual(report["labels"]["yolo_txt"], 1)
        self.assertFalse(report["mapping_verified"])

    def test_synthetic_coco_without_verified_mapping_keeps_metrics_null(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            coco = root / "synthetic-not-ground-truth.json"
            coco.write_text(
                json.dumps(
                    {
                        "info": {
                            "annotation_schema": "tariqmap-annotations-1",
                            "annotation_version": "test-1",
                            "provenance": "SYNTHETIC TEST FIXTURE NOT GROUND TRUTH",
                        },
                        "images": [{"id": 1, "file_name": "synthetic.jpg", "width": 32, "height": 32}],
                        "annotations": [
                            {
                                "id": 1,
                                "image_id": 1,
                                "category_id": 1,
                                "bbox": [1, 1, 4, 4],
                                "annotator_id": "synthetic-annotator",
                                "review_status": "accepted",
                                "provenance": "SYNTHETIC TEST FIXTURE NOT GROUND TRUTH",
                            }
                        ],
                        "categories": [
                            {
                                "id": 1,
                                "name": "pending-fixture-class",
                                "definition_status": "pending_confirmation",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--model",
                    str(MODEL),
                    "--dataset",
                    str(root),
                    "--annotations",
                    str(coco),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
        report = json.loads(completed.stdout)
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(report["status"], "NOT EVALUABLE")
        self.assertIsNone(report["metrics"])
        self.assertFalse(report["mapping_verified"])
        self.assertEqual(report["labels"]["candidate_schema"], "tariqmap-annotations-1")
        self.assertGreaterEqual(report["labels"]["label_files"], 1)

    def test_confirmed_candidate_with_verified_mapping_still_has_null_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            mapping = root / "mapping.json"
            mapping.write_text(
                json.dumps(
                    {
                        "mapping_status": "VERIFIED",
                        "evidence": ["SYNTHETIC TEST FIXTURE NOT GROUND TRUTH"],
                    }
                ),
                encoding="utf-8",
            )
            coco = root / "synthetic-confirmed.json"
            coco.write_text(
                json.dumps(
                    {
                        "info": {
                            "annotation_schema": "tariqmap-annotations-1",
                            "annotation_version": "test-1",
                            "provenance": "SYNTHETIC TEST FIXTURE NOT GROUND TRUTH",
                        },
                        "images": [{"id": 1, "file_name": "synthetic.jpg", "width": 32, "height": 32}],
                        "annotations": [
                            {
                                "id": 1,
                                "image_id": 1,
                                "category_id": 1,
                                "bbox": [1, 1, 4, 4],
                                "annotator_id": "synthetic-annotator",
                                "review_status": "accepted",
                                "provenance": "SYNTHETIC TEST FIXTURE NOT GROUND TRUTH",
                            }
                        ],
                        "categories": [
                            {
                                "id": 1,
                                "name": "pending-fixture-class",
                                "definition_status": "confirmed",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--model",
                    str(MODEL),
                    "--dataset",
                    str(root),
                    "--annotations",
                    str(coco),
                    "--mapping",
                    str(mapping),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
        report = json.loads(completed.stdout)
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(report["status"], "NOT EVALUABLE")
        self.assertIsNone(report["metrics"])
        self.assertTrue(report["mapping_verified"])
        blob = completed.stdout.lower()
        for banned in ("map50", "map@0.5", "precision", "recall", "f1"):
            self.assertNotIn(banned, blob)


if __name__ == "__main__":
    unittest.main()
