"""Synthetic duplicate report. No database connection."""
from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

from duplicate_diagnostic import classify_duplicates  # noqa: E402


class DuplicateDiagnosticTests(unittest.TestCase):
    def test_confirmed_duplicate_is_the_same_id(self):
        report = classify_duplicates(
            observations=[{"id": "obs-1"}, {"id": "obs-1"}],
            agent_runs=[{"id": "run-1", "observation_id": "obs-1", "agent": "road_damage"}],
            detections=[],
        )
        self.assertEqual(report["confirmed"], [{"kind": "observation", "id": "obs-1", "copies": 2}])
        self.assertEqual(report["deleted"], 0)
        self.assertEqual(report["merged"], 0)

    def test_possible_duplicates_keep_distinct_ids(self):
        report = classify_duplicates(
            observations=[
                {
                    "id": "obs-a",
                    "capture_id": "cap-1",
                    "latitude": 36.8,
                    "longitude": 10.18,
                    "captured_at": "2026-11-05T00:00:00+00:00",
                    "anomaly_type": "D40",
                },
                {
                    "id": "obs-b",
                    "capture_id": "cap-1",
                    "latitude": 36.8,
                    "longitude": 10.18,
                    "captured_at": "2026-11-05T00:00:30+00:00",
                    "anomaly_type": "D40",
                },
            ],
            agent_runs=[
                {"id": "run-old", "observation_id": "obs-a", "agent": "road_damage"},
                {"id": "run-new", "observation_id": "obs-a", "agent": "road_damage"},
            ],
            detections=[
                {"id": "det-old", "observation_id": "obs-a", "class_code": "D40", "box_x": 0.1, "box_y": 0.2, "box_w": 0.3, "box_h": 0.4},
                {"id": "det-new", "observation_id": "obs-a", "class_code": "D40", "box_x": 0.1, "box_y": 0.2, "box_w": 0.3, "box_h": 0.4},
            ],
        )
        kinds = {item["kind"] for item in report["possible"]}
        self.assertIn("observation_capture", kinds)
        self.assertIn("observation_place_time", kinds)
        self.assertIn("agent_run_same_agent", kinds)
        self.assertIn("detection_same_box", kinds)
        self.assertEqual(report["confirmed"], [])
        self.assertEqual(report["deleted"], 0)

    def test_distinct_classes_are_not_the_same_detection(self):
        report = classify_duplicates(
            observations=[{"id": "obs-1", "capture_id": "cap-9"}],
            agent_runs=[],
            detections=[
                {"id": "d1", "observation_id": "obs-1", "class_code": "D00", "box_x": 0.1, "box_y": 0.1, "box_w": 0.1, "box_h": 0.1},
                {"id": "d2", "observation_id": "obs-1", "class_code": "D40", "box_x": 0.1, "box_y": 0.1, "box_w": 0.1, "box_h": 0.1},
            ],
        )
        self.assertEqual(report["possible"], [])
        self.assertEqual(report["confirmed"], [])


if __name__ == "__main__":
    unittest.main()
