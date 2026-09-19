import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from src.convert_rdd_voc import voc_xml_to_yolo_lines, UNIFIED_IDS, convert
from src.analyze_labeled_dataset import analyze
from src.evaluate import evaluate
from src.verify_tflite import inspect_tflite
from src.prepare_dataset import prepare
from src.download_rdd import locate
from src.export import export_tflite
from src.check_environment import inspect


def _write_voc(path: Path, name: str, w=100, h=100, xmin=10, ymin=20, xmax=50, ymax=80) -> None:
    ann = ET.Element("annotation")
    ET.SubElement(ann, "filename").text = path.stem + ".jpg"
    size = ET.SubElement(ann, "size")
    ET.SubElement(size, "width").text = str(w)
    ET.SubElement(size, "height").text = str(h)
    obj = ET.SubElement(ann, "object")
    ET.SubElement(obj, "name").text = name
    box = ET.SubElement(obj, "bndbox")
    ET.SubElement(box, "xmin").text = str(xmin)
    ET.SubElement(box, "ymin").text = str(ymin)
    ET.SubElement(box, "xmax").text = str(xmax)
    ET.SubElement(box, "ymax").text = str(ymax)
    path.write_text(ET.tostring(ann, encoding="unicode"))


class RddConvertTests(unittest.TestCase):
    def test_d00_maps_to_class_0(self):
        with tempfile.TemporaryDirectory() as td:
            xml = Path(td) / "a.xml"
            _write_voc(xml, "D00")
            exclusions = []
            lines, counts = voc_xml_to_yolo_lines(xml, {"D00": "D00"}, exclusions)
            self.assertEqual(counts["D00"], 1)
            self.assertTrue(lines[0].startswith("0 "))
            self.assertEqual(exclusions, [])

    def test_d43_maps_to_d60(self):
        with tempfile.TemporaryDirectory() as td:
            xml = Path(td) / "a.xml"
            _write_voc(xml, "D43")
            exclusions = []
            lines, counts = voc_xml_to_yolo_lines(xml, {"D43": "D60"}, exclusions)
            self.assertEqual(counts["D60"], 1)
            self.assertTrue(lines[0].startswith(f"{UNIFIED_IDS['D60']} "))

    def test_d44_maps_to_d50(self):
        with tempfile.TemporaryDirectory() as td:
            xml = Path(td) / "a.xml"
            _write_voc(xml, "D44")
            exclusions = []
            lines, counts = voc_xml_to_yolo_lines(xml, {"D44": "D50"}, exclusions)
            self.assertEqual(counts["D50"], 1)
            self.assertTrue(lines[0].startswith(f"{UNIFIED_IDS['D50']} "))

    def test_rdd_d50_other_is_excluded(self):
        with tempfile.TemporaryDirectory() as td:
            xml = Path(td) / "a.xml"
            _write_voc(xml, "D50")
            exclusions = []
            # Converter lookup does not map raw D50 (RDD other) to TariqMap D50
            lines, counts = voc_xml_to_yolo_lines(xml, {"D44": "D50"}, exclusions)
            self.assertEqual(lines, [])
            self.assertEqual(len(exclusions), 1)

    def test_d90_never_emitted(self):
        with tempfile.TemporaryDirectory() as td:
            xml = Path(td) / "a.xml"
            _write_voc(xml, "D90")
            exclusions = []
            lines, _ = voc_xml_to_yolo_lines(xml, {"D90": "D90"}, exclusions)
            self.assertEqual(lines, [])
            self.assertTrue(exclusions)

    def test_full_convert_copies_image_and_label(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td) / "rdd"
            src.mkdir()
            _write_voc(src / "im.xml", "D40")
            (src / "im.jpg").write_bytes(b"not-a-real-jpeg")
            out = Path(td) / "yolo"
            class_map = ROOT / "config" / "source-class-map.json"
            summary = convert(src, out, class_map)
            self.assertEqual(summary["converted_images"], 1)
            self.assertEqual(summary["class_distribution"]["D40"], 1)
            self.assertEqual(summary["d90_emitted"], 0)
            self.assertTrue((out / "labels" / "im.txt").exists())


class AnalyzeTests(unittest.TestCase):
    def test_unlabeled_dir_is_stop(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td)
            (p / "x.jpg").write_bytes(b"x")
            report = analyze(p)
            self.assertIn("STOP", report["verdict"])
            self.assertEqual(report["d90_status"], "ABSENT")

    def test_labeled_distribution(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td)
            (p / "labels").mkdir()
            (p / "images").mkdir()
            (p / "images" / "a.jpg").write_bytes(b"x")
            (p / "labels" / "a.txt").write_text("3 0.5 0.5 0.2 0.2\n")
            report = analyze(p)
            self.assertEqual(report["class_distribution"]["D40"], 1)
            self.assertIn("D90", report["missing_classes"])


class EvaluateGuardTests(unittest.TestCase):
    def test_missing_weights_is_not_run(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "eval.json"
            report = evaluate(Path(td) / "missing.pt", Path(td) / "missing.yaml", "test", 640, out)
            self.assertEqual(report["status"], "NOT_RUN")
            self.assertIsNone(report["metrics"])


class VerifyTfliteTests(unittest.TestCase):
    def test_missing_model_is_pending(self):
        report = inspect_tflite(Path("/no/such/model.tflite"))
        self.assertEqual(report["status"], "MODEL_PENDING")
        self.assertFalse(report["ok_for_flutter"])


class PrepareGuardTests(unittest.TestCase):
    def test_refuses_global_potholes_name(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td) / "Global_Potholes_Dataset-image"
            src.mkdir()
            (src / "a.jpg").write_bytes(b"x")
            with self.assertRaises(SystemExit) as ctx:
                prepare(src, Path(td) / "out", ROOT / "config" / "source-class-map.json", (0.7, 0.15, 0.15))
            self.assertIn("STOP", str(ctx.exception))


class DownloadLocateTests(unittest.TestCase):
    def test_empty_dir_is_not_usable(self):
        with tempfile.TemporaryDirectory() as td:
            report = locate(Path(td))
            self.assertFalse(report["usable"])
            self.assertEqual(report["xml_count"], 0)


class ExportGuardTests(unittest.TestCase):
    def test_missing_weights_is_not_run(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(SystemExit) as ctx:
                export_tflite(Path(td) / "missing.pt", "pavement", Path(td) / "out")
            self.assertIn("NOT_RUN", str(ctx.exception))


class EnvironmentTests(unittest.TestCase):
    def test_reports_labeled_missing_without_inventing_cuda(self):
        with tempfile.TemporaryDirectory() as td:
            report = inspect(ROOT, Path(td) / "no-rdd")
            self.assertFalse(report["labeled_extract"]["usable"])
            self.assertFalse(report["can_train_yolov8"])
            self.assertIn("cuda", report)


if __name__ == "__main__":
    unittest.main()
