"""WP3 Colab-readiness tests. Does not start YOLOv8 training."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from src.verify_wp3_dataset import EXPECTED_COUNTS, verify, write_colab_yaml
from src.eval_wp3 import evaluate_wp3
from src.eval_small_objects import analyze_split, _bin_name
from src.verify_tflite import inspect_tflite
from src.pack_wp3_artifacts import pack
from evaluation.compare_wp3_models import compare


def _write_yolo_pair(root: Path, split: str, stem: str, line: str, size: tuple[int, int] | None = None) -> None:
    (root / "images" / split).mkdir(parents=True, exist_ok=True)
    (root / "labels" / split).mkdir(parents=True, exist_ok=True)
    img = root / "images" / split / f"{stem}.jpg"
    if size is not None:
        try:
            from PIL import Image
            Image.new("RGB", size, (8, 8, 8)).save(img, format="JPEG")
        except ImportError:
            img.write_bytes(b"not-a-jpeg")
    else:
        img.write_bytes(b"not-a-jpeg")
    (root / "labels" / split / f"{stem}.txt").write_text(line + "\n")


class VerifyWp3Tests(unittest.TestCase):
    def test_yaml_names_are_d20_d40_only(self):
        yaml = (ROOT / "config" / "pavement.yaml").read_text()
        self.assertIn("0: D20", yaml)
        self.assertIn("1: D40", yaml)
        self.assertNotIn("D00", yaml.split("names:")[-1])
        self.assertEqual(EXPECTED_COUNTS["train_images"], 7380)
        self.assertEqual(EXPECTED_COUNTS["val_images"], 1581)
        self.assertEqual(EXPECTED_COUNTS["test_images"], 1582)
        self.assertEqual(EXPECTED_COUNTS["total_boxes"], 17160)

    def test_valid_fixture_without_expected_counts(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "pavement"
            _write_yolo_pair(root, "train", "a", "0 0.5 0.5 0.2 0.2")
            _write_yolo_pair(root, "val", "b", "1 0.4 0.4 0.1 0.1")
            _write_yolo_pair(root, "test", "c", "0 0.3 0.3 0.2 0.2")
            yaml = Path(td) / "pavement.yaml"
            yaml.write_text("path: x\nnames:\n  0: D20\n  1: D40\n")
            report = verify(root, yaml, check_expected_counts=False)
            self.assertEqual(report["status"], "OK")
            self.assertEqual(report["split_images"]["train"], 1)
            self.assertEqual(report["box_counts_by_name"]["D20"], 2)
            self.assertEqual(report["box_counts_by_name"]["D40"], 1)

    def test_rejects_non_wp3_class_id(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "pavement"
            _write_yolo_pair(root, "train", "a", "2 0.5 0.5 0.2 0.2")
            _write_yolo_pair(root, "val", "b", "1 0.4 0.4 0.1 0.1")
            _write_yolo_pair(root, "test", "c", "0 0.3 0.3 0.2 0.2")
            report = verify(root, None, check_expected_counts=False)
            self.assertEqual(report["status"], "FAIL")
            self.assertTrue(any("class id 2" in e for e in report["errors"]))

    def test_rejects_wrong_yaml_names(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "pavement"
            _write_yolo_pair(root, "train", "a", "0 0.5 0.5 0.2 0.2")
            _write_yolo_pair(root, "val", "b", "1 0.4 0.4 0.1 0.1")
            _write_yolo_pair(root, "test", "c", "0 0.3 0.3 0.2 0.2")
            yaml = Path(td) / "bad.yaml"
            yaml.write_text("names:\n  0: D00\n  1: D10\n")
            report = verify(root, yaml, check_expected_counts=False)
            self.assertEqual(report["status"], "FAIL")

    def test_write_colab_yaml_uses_absolute_path(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "pavement.colab.yaml"
            write_colab_yaml(Path(td) / "pavement", dest)
            text = dest.read_text()
            self.assertIn("0: D20", text)
            self.assertIn(str((Path(td) / "pavement").resolve()), text)


class EvalWp3GuardTests(unittest.TestCase):
    def test_missing_weights_is_not_run(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "metrics.json"
            report = evaluate_wp3(
                Path(td) / "missing.pt",
                ROOT / "config" / "pavement.yaml",
                "test",
                640,
                out,
                "baseline",
            )
            self.assertEqual(report["status"], "NOT_RUN")
            self.assertIsNone(report["metrics"])
            loaded = json.loads(out.read_text())
            self.assertIsNone(loaded["metrics"])


class SmallObjectBinTests(unittest.TestCase):
    def test_bin_edges(self):
        self.assertEqual(_bin_name(31.9), "lt_32")
        self.assertEqual(_bin_name(32.0), "32_64")
        self.assertEqual(_bin_name(63.9), "32_64")
        self.assertEqual(_bin_name(64.0), "gt_64")

    def test_synthetic_boxes(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            # 100x100 image: 0.1*100=10px -> lt_32; 0.4=40 -> 32_64; 0.8=80 -> gt_64
            _write_yolo_pair(root, "test", "a", "0 0.5 0.5 0.1 0.1", size=(100, 100))
            _write_yolo_pair(root, "test", "b", "1 0.5 0.5 0.4 0.4", size=(100, 100))
            _write_yolo_pair(root, "test", "c", "1 0.5 0.5 0.8 0.8", size=(100, 100))
            report = analyze_split(root, "test")
            if report["status"] != "OK":
                self.skipTest(report.get("reason") or "image sizes unavailable")
            self.assertEqual(report["per_class"]["D20"]["lt_32"], 1)
            self.assertEqual(report["per_class"]["D40"]["32_64"], 1)
            self.assertEqual(report["per_class"]["D40"]["gt_64"], 1)


class CompareWp3Tests(unittest.TestCase):
    def test_not_run_fixtures_do_not_declare_better(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            a = td / "base.json"
            b = td / "imp.json"
            a.write_text(json.dumps({"status": "NOT_RUN", "metrics": None}))
            b.write_text(json.dumps({"status": "NOT_RUN", "metrics": None}))
            report = compare(a, b, td / "out.json")
            self.assertEqual(report["status"], "NOT_RUN")
            self.assertFalse(report["declare_better"])
            self.assertIn("NOT_RUN", report["markdown_table"])

    def test_ok_metrics_can_declare_better(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)

            def payload(p, r, m50, d20, d40):
                return {
                    "status": "OK",
                    "metrics": {
                        "precision": p,
                        "recall": r,
                        "F1": 2 * p * r / (p + r),
                        "mAP50": m50,
                        "mAP50-95": m50 - 0.1,
                        "per_class": {
                            "D20": {"precision": p, "recall": r, "F1": 2 * p * r / (p + r), "AP50": d20, "AP50-95": d20 - 0.05},
                            "D40": {"precision": p, "recall": r, "F1": 2 * p * r / (p + r), "AP50": d40, "AP50-95": d40 - 0.05},
                        },
                    },
                }

            (td / "base.json").write_text(json.dumps(payload(0.5, 0.4, 0.45, 0.4, 0.3)))
            (td / "imp.json").write_text(json.dumps(payload(0.6, 0.5, 0.55, 0.5, 0.4)))
            report = compare(td / "base.json", td / "imp.json", td / "out.json")
            self.assertEqual(report["status"], "OK")
            self.assertTrue(report["declare_better"])


class TflitePendingTests(unittest.TestCase):
    def test_missing_model_is_pending(self):
        report = inspect_tflite(Path("/no/such/model.tflite"), expected_classes=2)
        self.assertEqual(report["status"], "MODEL_PENDING")
        self.assertFalse(report["ok_for_flutter"])
        self.assertEqual(report["expected_classes"], 2)


class PackArtifactsTests(unittest.TestCase):
    def test_pack_without_weights_is_not_run_not_fake(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "config").mkdir()
            (root / "config" / "pavement.yaml").write_text("names:\n  0: D20\n  1: D40\n")
            out = root / "wp3_training_artifacts.zip"
            manifest = pack(root, out)
            self.assertTrue(out.exists())
            self.assertEqual(manifest["weight_files"], [])
            self.assertEqual(manifest["status"], "NOT_RUN")
            self.assertTrue(any("pavement.yaml" in p for p in manifest["included"]))


if __name__ == "__main__":
    unittest.main()
