import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from src.convert_rdd_voc import voc_xml_to_yolo_lines, UNIFIED_IDS, convert, _index_images
from src.analyze_labeled_dataset import analyze
from src.analyze_voc import analyze_voc
from src.evaluate import evaluate
from src.verify_tflite import inspect_tflite
from src.prepare_dataset import prepare
from src.download_rdd import locate, can_download, EXPECTED_ZIP_BYTES
from src.summarize_file_list import summarize
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

    def test_nested_rdd_layout_finds_train_images(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "RDD2022"
            xml_dir = root / "Japan" / "train" / "annotations" / "xmls"
            img_dir = root / "Japan" / "train" / "images"
            xml_dir.mkdir(parents=True)
            img_dir.mkdir(parents=True)
            _write_voc(xml_dir / "Japan_000.xml", "D00")
            (img_dir / "Japan_000.jpg").write_bytes(b"jpeg")
            # unlabeled test image must not steal the stem
            test_dir = root / "Japan" / "test" / "images"
            test_dir.mkdir(parents=True)
            (test_dir / "Japan_000.jpg").write_bytes(b"other")
            index = _index_images(root)
            self.assertEqual(index["Japan_000"].parent, img_dir)
            out = Path(td) / "yolo"
            summary = convert(root, out, ROOT / "config" / "source-class-map.json")
            self.assertEqual(summary["converted_images"], 1)
            self.assertEqual(summary["skipped_missing_image"], 0)
            self.assertTrue((out / "images" / "Japan_000.jpg").exists())


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

    def test_splits_d40_to_pavement_agent_only(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td) / "yolo"
            (src / "images").mkdir(parents=True)
            (src / "labels").mkdir()
            (src / "images" / "hole.jpg").write_bytes(b"x")
            (src / "labels" / "hole.txt").write_text("3 0.5 0.5 0.2 0.2\n")
            out = Path(td) / "processed"
            summary = prepare(
                src, out, ROOT / "config" / "source-class-map.json", (0.7, 0.15, 0.15)
            )
            self.assertEqual(summary["class_distribution"]["D40"], 1)
            self.assertEqual(summary["agent_image_counts"]["pavement"], 1)
            self.assertEqual(summary["agent_image_counts"]["cracks"], 0)
            self.assertEqual(summary["agent_image_counts"]["surface"], 0)
            pavement_labels = list((out / "pavement").rglob("*.txt"))
            self.assertTrue(pavement_labels)
            self.assertTrue(pavement_labels[0].read_text().startswith("1 "))  # D40 → local id 1
            self.assertFalse(list((out / "cracks").rglob("*.txt")))


class VocAnalyzeTests(unittest.TestCase):
    def test_counts_raw_and_mapped_and_excludes_rdd_d50(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td)
            _write_voc(src / "a.xml", "D00", xmin=10, ymin=10, xmax=80, ymax=80)
            _write_voc(src / "b.xml", "D43", xmin=10, ymin=10, xmax=40, ymax=40)
            _write_voc(src / "c.xml", "D50", xmin=10, ymin=10, xmax=40, ymax=40)
            report = analyze_voc(src, ROOT / "config" / "source-class-map.json")
            self.assertEqual(report["xml_count"], 3)
            self.assertEqual(report["raw_class_distribution"]["D00"], 1)
            self.assertEqual(report["raw_class_distribution"]["D43"], 1)
            self.assertEqual(report["mapped_tariqmap_distribution"]["D00"], 1)
            self.assertEqual(report["mapped_tariqmap_distribution"]["D60"], 1)
            self.assertEqual(report["unmapped_class_distribution"]["D50"], 1)
            self.assertEqual(report["d90_mapped_status"], "ABSENT")
            self.assertEqual(report["d50_mapped_status"], "ABSENT")
            self.assertEqual(report["d60_mapped_status"], "PRESENT")

    def test_flags_degenerate_box(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td)
            _write_voc(src / "bad.xml", "D40", xmin=10, ymin=10, xmax=10, ymax=12)
            report = analyze_voc(src, ROOT / "config" / "source-class-map.json")
            self.assertGreaterEqual(report["issue_counts"].get("degenerate_box", 0), 1)


class FileListTests(unittest.TestCase):
    def test_counts_xml_and_unlabeled_test_images(self):
        with tempfile.TemporaryDirectory() as td:
            listing = Path(td) / "File_List.txt"
            listing.write_text(
                "\n".join(
                    [
                        "C:.",
                        "+---Japan",
                        "|   +---test",
                        "|   |   \\---images",
                        "|   |           Japan_t.jpg",
                        "|   \\---train",
                        "|       +---annotations",
                        "|       |   \\---xmls",
                        "|       |           Japan_000.xml",
                        "|       \\---images",
                        "|               Japan_000.jpg",
                        "\\---Czech",
                        "    \\---train",
                        "        +---annotations",
                        "        |   \\---xmls",
                        "        |           Czech_000.xml",
                        "        \\---images",
                        "                Czech_000.jpg",
                    ]
                )
            )
            report = summarize(listing)
            self.assertEqual(report["xml_total"], 2)
            self.assertEqual(report["image_total"], 3)
            self.assertEqual(report["unlabeled_test_images"], 1)
            self.assertEqual(report["per_country"]["Japan"]["train"]["xml"], 1)
            self.assertEqual(report["per_country"]["Japan"]["test"]["image"], 1)
            self.assertEqual(report["kind"], "official_file_inventory_not_class_labels")


class DownloadGuardTests(unittest.TestCase):
    def test_empty_dir_is_not_usable(self):
        with tempfile.TemporaryDirectory() as td:
            report = locate(Path(td))
            self.assertFalse(report["usable"])
            self.assertEqual(report["xml_count"], 0)

    def test_can_download_requires_slack(self):
        self.assertTrue(can_download(EXPECTED_ZIP_BYTES + 3 * 1024 ** 3, EXPECTED_ZIP_BYTES))
        self.assertFalse(can_download(1000, EXPECTED_ZIP_BYTES))
        self.assertTrue(can_download(0, 0))


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
            self.assertIn("disk", report)
            self.assertGreater(report["disk"]["free_bytes"], 0)


if __name__ == "__main__":
    unittest.main()
