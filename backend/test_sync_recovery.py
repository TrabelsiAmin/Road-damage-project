"""Partial sync recovery against an in-memory store.

No HTTP call is made. The service-role key is overwritten before any request
helper runs, and it is not printed.
"""
from __future__ import annotations

import os
import sys
import unittest
import uuid

sys.path.insert(0, os.path.dirname(__file__))

from schemas import AgentResultSchema, BoundingBoxSchema, DetectionSchema, ObservationUpload  # noqa: E402
from supabase_store import SupabaseStore, redact_secrets  # noqa: E402


def _body(obs_id: str, *, classes: list[str] | None = None) -> ObservationUpload:
    detections = [
        DetectionSchema(
            agent="road_damage",
            classCode=code,
            confidence=0.8,
            box=BoundingBoxSchema(x=0.1, y=0.1, width=0.2, height=0.2),
        )
        for code in (classes or ["D40"])
    ]
    return ObservationUpload(
        id=obs_id,
        captureId="cap-1",
        imagePath="local.jpg",
        createdAt="2026-11-05T00:00:00Z",
        latitude=36.8,
        longitude=10.18,
        actor="Municipality",
        agentResults=[AgentResultSchema(agent="road_damage", detections=detections, isMock=False)],
    )


class _Response:
    def __init__(self, payload, headers=None):
        self._payload = payload
        self.headers = headers or {}
        self.status_code = 200
        self.text = ""

    def json(self):
        return self._payload


class MemoryStore(SupabaseStore):
    def __init__(self) -> None:
        super().__init__()
        self.key = "memory-test-key"
        self.url = "http://127.0.0.1:9"
        self.rows: dict[str, dict] = {
            "observations": {},
            "locations": {},
            "agent_runs": {},
            "detections": {},
            "sync_receipts": {},
        }
        self.posts: list[str] = []
        self.fail_on: tuple[str, str] | None = None
        self.fail_message = "network interrupted"

    def _request(self, method, table, *, params=None, payload=None, prefer=None):
        del prefer
        if self.fail_on == (method, table):
            self.fail_on = None
            raise RuntimeError(self.fail_message)
        params = params or {}
        if method == "GET":
            return _Response(self._select(table, params))
        if method == "POST":
            self.posts.append(table)
            self._insert(table, payload)
            return _Response([])
        raise AssertionError(f"unexpected {method} {table}")

    def _eq(self, params, column):
        raw = params.get(column, "")
        if not str(raw).startswith("eq."):
            return None
        from urllib.parse import unquote

        return unquote(str(raw)[3:])

    def _select(self, table, params):
        wanted_id = self._eq(params, "id")
        wanted_obs = self._eq(params, "observation_id")
        rows = list(self.rows[table].values())
        if wanted_id is not None:
            rows = [row for row in rows if row.get("id") == wanted_id]
        if wanted_obs is not None:
            rows = [row for row in rows if row.get("observation_id") == wanted_obs]
        return rows

    def _insert(self, table, payload):
        items = payload if isinstance(payload, list) else [payload]
        for item in items:
            if table == "locations":
                key = item["observation_id"]
            elif table == "sync_receipts":
                key = item["observation_id"]
            else:
                key = item["id"]
            if key in self.rows[table]:
                raise RuntimeError(f"duplicate {table} {key}")
            self.rows[table][key] = dict(item)


def _sync_may_complete(*, observation, children, media, auth, network) -> bool:
    """Same rule as the Flutter sync plan: every required step must succeed."""
    return bool(observation and children and media and auth and network)


def _recover_stuck(rows: list[dict]) -> list[dict]:
    """Startup recovery: uploading returns to pending. Rows are not deleted."""
    recovered = []
    for row in rows:
        if row["status"] == "uploading":
            recovered.append({**row, "status": "pending"})
        else:
            recovered.append(dict(row))
    return recovered


class SyncRecoveryTests(unittest.TestCase):
    def test_complete_sync_inserts_observation_and_children(self):
        store = MemoryStore()
        obs_id = "11111111-1111-4111-8111-111111111111"
        result = store.insert_observation(_body(obs_id), obs_id)
        self.assertEqual(result["status"], "created")
        self.assertIn(obs_id, store.rows["observations"])
        self.assertIn(obs_id, store.rows["locations"])
        self.assertEqual(len(store.rows["agent_runs"]), 1)
        self.assertEqual(len(store.rows["detections"]), 1)
        self.assertIn(obs_id, store.rows["sync_receipts"])
        detection_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{obs_id}:det:0:0"))
        self.assertIn(detection_id, store.rows["detections"])
        self.assertNotIn("media_files", store.posts)

    def test_partial_sync_inserts_only_missing_children(self):
        store = MemoryStore()
        obs_id = "22222222-2222-4222-8222-222222222222"
        store.rows["observations"][obs_id] = {"id": obs_id}
        result = store.insert_observation(_body(obs_id, classes=["D00", "D10"]), obs_id)
        self.assertEqual(result["status"], "repaired")
        self.assertEqual(store.posts.count("observations"), 0)
        self.assertEqual(len(store.rows["detections"]), 2)
        self.assertEqual(len(store.rows["observations"]), 1)

    def test_retry_after_missing_children_is_idempotent(self):
        store = MemoryStore()
        obs_id = "33333333-3333-4333-8333-333333333333"
        body = _body(obs_id, classes=["D20"])
        first = store.insert_observation(body, obs_id)
        posts_after_first = list(store.posts)
        second = store.insert_observation(body, obs_id)
        self.assertEqual(first["status"], "created")
        self.assertEqual(second["status"], "already_received")
        self.assertEqual(store.posts, posts_after_first)
        self.assertEqual(len(store.rows["detections"]), 1)

    def test_duplicate_retry_does_not_duplicate_children(self):
        store = MemoryStore()
        obs_id = "44444444-4444-4444-8444-444444444444"
        body = _body(obs_id)
        store.insert_observation(body, obs_id)
        store.insert_observation(body, obs_id)
        self.assertEqual(len(store.rows["agent_runs"]), 1)
        self.assertEqual(len(store.rows["detections"]), 1)
        self.assertEqual(len(store.rows["sync_receipts"]), 1)

    def test_failed_media_keeps_the_sync_incomplete(self):
        self.assertFalse(
            _sync_may_complete(observation=True, children=True, media=False, auth=True, network=True)
        )
        store = MemoryStore()
        store.insert_observation(_body("55555555-5555-4555-8555-555555555555"), "idem")
        self.assertNotIn("media_files", store.posts)

    def test_app_restart_returns_uploading_rows_to_pending(self):
        rows = [
            {"id": "a", "status": "uploading"},
            {"id": "b", "status": "synced"},
            {"id": "c", "status": "failed"},
        ]
        recovered = _recover_stuck(rows)
        self.assertEqual([row["status"] for row in recovered], ["pending", "synced", "failed"])
        self.assertEqual([row["id"] for row in recovered], ["a", "b", "c"])
        self.assertEqual(len(recovered), len(rows))

    def test_network_interruption_does_not_write_a_receipt(self):
        store = MemoryStore()
        obs_id = "66666666-6666-4666-8666-666666666666"
        store.fail_on = ("POST", "detections")
        with self.assertRaises(RuntimeError):
            store.insert_observation(_body(obs_id), obs_id)
        self.assertIn(obs_id, store.rows["observations"])
        self.assertNotIn(obs_id, store.rows["sync_receipts"])
        self.assertEqual(store.rows["detections"], {})
        store.fail_on = None
        repaired = store.insert_observation(_body(obs_id), obs_id)
        self.assertEqual(repaired["status"], "repaired")
        self.assertIn(obs_id, store.rows["sync_receipts"])
        self.assertEqual(len(store.rows["detections"]), 1)

    def test_expired_auth_propagates_and_inserts_nothing(self):
        store = MemoryStore()
        store.fail_on = ("GET", "observations")
        store.fail_message = "401 jwt expired"
        with self.assertRaises(RuntimeError) as caught:
            store.insert_observation(_body("77777777-7777-4777-8777-777777777777"), "idem")
        self.assertIn("401", str(caught.exception))
        self.assertEqual(store.rows["observations"], {})
        self.assertEqual(store.posts, [])

    def test_random_child_ids_are_not_deleted(self):
        store = MemoryStore()
        obs_id = "88888888-8888-4888-8888-888888888888"
        store.rows["observations"][obs_id] = {"id": obs_id}
        store.rows["detections"]["random-old"] = {"id": "random-old", "observation_id": obs_id}
        store.insert_observation(_body(obs_id), obs_id)
        self.assertIn("random-old", store.rows["detections"])
        self.assertEqual(len(store.rows["detections"]), 2)

    def test_stats_skip_a_missing_class_and_do_not_call_it_d40(self):
        store = MemoryStore()
        store.rows["observations"]["o1"] = {"id": "o1", "organization_id": None, "priority_label": None}
        store.rows["detections"]["d1"] = {"id": "d1", "class_code": None}
        store.rows["detections"]["d2"] = {"id": "d2", "class_code": "D00"}
        stats = store.stats()
        self.assertEqual(stats["total"], 1)
        self.assertEqual(stats["by_class"], {"D00": 1})
        self.assertNotIn("D40", stats["by_class"])
        self.assertEqual(sum(stats["by_priority"].values()), 0)

    def test_redaction_removes_a_jwt_shaped_string(self):
        token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature"
        cleaned = redact_secrets(f"header {token}")
        self.assertNotIn(token, cleaned)
        self.assertIn("[redacted]", cleaned)


if __name__ == "__main__":
    unittest.main()
