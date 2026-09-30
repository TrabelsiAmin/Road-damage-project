"""Backend lifecycle constants — no GIS/RAG product."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from lifecycle import (
    ACTORS,
    ACTORS_FR,
    INCIDENT_STATUSES,
    INCIDENT_TRANSITIONS,
    RAG_ROLE,
    can_transition,
)


class LifecycleTests(unittest.TestCase):
    def test_incident_chain_matches_validated_conception(self):
        self.assertEqual(
            list(INCIDENT_STATUSES),
            [
                "DETECTED",
                "ANALYZED",
                "ASSIGNED",
                "IN_PROGRESS",
                "RESOLVED",
                "ARCHIVED",
            ],
        )

    def test_forward_only_transitions(self):
        self.assertTrue(can_transition("DETECTED", "ANALYZED"))
        self.assertTrue(can_transition("RESOLVED", "ARCHIVED"))
        self.assertFalse(can_transition("DETECTED", "ASSIGNED"))
        self.assertFalse(can_transition("ARCHIVED", "DETECTED"))
        self.assertEqual(INCIDENT_TRANSITIONS["ARCHIVED"], ())

    def test_three_peer_actors(self):
        self.assertEqual(len(ACTORS), 3)
        self.assertEqual(len(ACTORS_FR), 3)
        self.assertEqual(RAG_ROLE, "decision_support_only")

    def test_gps_missing_payload_is_accepted(self):
        try:
            from schemas import ObservationUpload
        except ImportError:
            self.skipTest("pydantic/fastapi not installed")
        body = ObservationUpload(
            id="obs-0",
            captureId="cap-0",
            imagePath="/tmp/a.jpg",
            createdAt="2026-09-20T00:00:00Z",
            latitude=0.0,
            longitude=0.0,
            gpsAvailable=False,
            actor="Municipality",
            agentResults=[],
        )
        self.assertFalse(body.gpsAvailable)
        self.assertEqual(body.latitude, 0.0)


if __name__ == "__main__":
    unittest.main()
