"""Tests for the KD pipeline stub. No metrics are invented."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from src.distill import AGENTS, KD_RECIPE, PRIORITY_AGENT, plan


class DistillStubTests(unittest.TestCase):
    def test_three_agents_remain_disjoint(self):
        self.assertEqual(AGENTS["cracks"], ["D00", "D10"])
        self.assertEqual(AGENTS["pavement"], ["D20", "D40"])
        self.assertEqual(AGENTS["surface"], ["D50", "D60", "D90"])
        seen: set[str] = set()
        for codes in AGENTS.values():
            for code in codes:
                self.assertNotIn(code, seen)
                seen.add(code)

    def test_wp3_pavement_is_priority(self):
        self.assertEqual(PRIORITY_AGENT, "pavement")
        self.assertEqual(AGENTS[PRIORITY_AGENT], ["D20", "D40"])
        self.assertTrue(KD_RECIPE["no_depth_estimation"])
        self.assertEqual(KD_RECIPE["deploy_as"], "three_independent_tflite_runners")

    def test_missing_teacher_is_not_run_without_metrics(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "plan.json"
            report = plan(
                agent="pavement",
                teacher=Path(td) / "missing_teacher.pt",
                student=Path("yolov8n.pt"),
                data=ROOT / "config" / "pavement.yaml",
                output=out,
            )
            self.assertEqual(report["status"], "NOT_RUN")
            self.assertIsNone(report["metrics"])
            self.assertIn("missing", report["reason"].lower())
            loaded = json.loads(out.read_text())
            self.assertIsNone(loaded["metrics"])

    def test_unknown_agent_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(SystemExit):
                plan(
                    agent="unified",
                    teacher=Path(td) / "t.pt",
                    student=Path("yolov8n.pt"),
                    data=ROOT / "config" / "pavement.yaml",
                    output=Path(td) / "out.json",
                )


if __name__ == "__main__":
    unittest.main()
