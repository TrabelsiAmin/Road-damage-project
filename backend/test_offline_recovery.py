"""Offline sync state machine. No network and no Supabase.

Mirrors the Flutter rules: local rows stay, synced is only set when every
required step succeeded, retries reuse ids, and the attempt cap stops the loop.
"""
from __future__ import annotations

import unittest
import uuid


MAX_ATTEMPTS = 5
BACKOFF_CAP_SECONDS = 300


def stable_ids(observation_id: str) -> dict[str, str]:
    return {
        "run": str(uuid.uuid5(uuid.NAMESPACE_URL, f"{observation_id}:agent:0:road_damage")),
        "detection": str(uuid.uuid5(uuid.NAMESPACE_URL, f"{observation_id}:det:0:0")),
        "media": str(uuid.uuid5(uuid.NAMESPACE_URL, f"{observation_id}:original")),
    }


def backoff_seconds(attempt: int) -> int:
    return min(2 * (2**attempt), BACKOFF_CAP_SECONDS)


class LocalRow:
    def __init__(self, observation_id: str):
        self.id = observation_id
        self.status = "pending"
        self.media = "pending"
        self.attempts = 0
        self.error = None
        self.deleted = False


class Remote:
    def __init__(self):
        self.observations = set()
        self.children = set()
        self.receipts = set()
        self.media = set()
        self.fail = None

    def submit(self, row: LocalRow, ids: dict[str, str], *, have_file: bool, auth: bool, network: bool):
        if not network:
            raise RuntimeError("network interrupted")
        if not auth:
            raise RuntimeError("401 jwt expired")
        if self.fail == "observation" and row.id not in self.observations:
            raise RuntimeError("observation insert failed")
        self.observations.add(row.id)
        if self.fail == "children" and ids["detection"] not in self.children:
            raise RuntimeError("child insert failed")
        self.children.add(ids["run"])
        self.children.add(ids["detection"])
        if row.id not in self.observations or ids["detection"] not in self.children:
            raise RuntimeError("receipt blocked")
        self.receipts.add(row.id)
        if row.media != "uploaded":
            if not have_file:
                row.media = "failed"
                raise RuntimeError("local image is missing")
            if self.fail == "media":
                row.media = "failed"
                raise RuntimeError("media upload failed")
            self.media.add(ids["media"])
            row.media = "uploaded"


def recover_stuck(rows: list[LocalRow]) -> None:
    for row in rows:
        if row.status == "uploading":
            row.status = "pending"


def sync_once(row: LocalRow, remote: Remote, *, have_file=True, auth=True, network=True) -> None:
    if row.deleted:
        raise AssertionError("local row was deleted")
    if row.status in ("synced", "needs_review"):
        return
    if row.attempts >= MAX_ATTEMPTS:
        row.status = "needs_review"
        return
    row.status = "uploading"
    ids = stable_ids(row.id)
    try:
        remote.submit(row, ids, have_file=have_file, auth=auth, network=network)
    except RuntimeError as exc:
        row.status = "failed"
        row.attempts += 1
        row.error = str(exc)
        return
    if row.media != "uploaded" or row.id not in remote.receipts:
        row.status = "failed"
        row.attempts += 1
        return
    row.status = "synced"
    row.error = None


class OfflineRecoveryTests(unittest.TestCase):
    def test_offline_capture_stays_pending_until_reconnect(self):
        row = LocalRow("obs-1")
        remote = Remote()
        sync_once(row, remote, network=False)
        self.assertEqual(row.status, "failed")
        self.assertFalse(row.deleted)
        self.assertEqual(remote.observations, set())
        sync_once(row, remote, network=True)
        self.assertEqual(row.status, "synced")
        self.assertIn(stable_ids(row.id)["detection"], remote.children)

    def test_auth_expiry_and_failed_inserts_do_not_mark_synced(self):
        row = LocalRow("obs-2")
        remote = Remote()
        sync_once(row, remote, auth=False)
        self.assertEqual(row.status, "failed")
        self.assertNotIn(row.id, remote.observations)

        remote.fail = "observation"
        sync_once(row, remote)
        self.assertEqual(row.status, "failed")
        self.assertEqual(remote.receipts, set())

        remote.fail = "children"
        sync_once(row, remote)
        self.assertEqual(row.status, "failed")
        self.assertIn(row.id, remote.observations)
        self.assertNotIn(row.id, remote.receipts)

    def test_failed_media_keeps_the_row_and_retries_the_same_media_id(self):
        row = LocalRow("obs-3")
        remote = Remote()
        remote.fail = "media"
        sync_once(row, remote)
        self.assertEqual(row.status, "failed")
        self.assertEqual(row.media, "failed")
        self.assertIn(row.id, remote.receipts)
        media_id = stable_ids(row.id)["media"]
        remote.fail = None
        sync_once(row, remote)
        self.assertEqual(row.status, "synced")
        self.assertEqual(remote.media, {media_id})

    def test_missing_local_file_is_not_synced(self):
        row = LocalRow("obs-4")
        remote = Remote()
        sync_once(row, remote, have_file=False)
        self.assertEqual(row.status, "failed")
        self.assertEqual(remote.media, set())

    def test_kill_during_upload_returns_to_pending_without_deletion(self):
        row = LocalRow("obs-5")
        row.status = "uploading"
        recover_stuck([row])
        self.assertEqual(row.status, "pending")
        self.assertFalse(row.deleted)

    def test_attempt_cap_stops_the_loop_and_duplicate_calls_do_not_copy_children(self):
        row = LocalRow("obs-6")
        remote = Remote()
        remote.fail = "media"
        for _ in range(MAX_ATTEMPTS + 1):
            sync_once(row, remote)
        self.assertEqual(row.status, "needs_review")
        self.assertLessEqual(row.attempts, MAX_ATTEMPTS)
        self.assertEqual(len(remote.children), 2)
        self.assertGreater(backoff_seconds(8), backoff_seconds(1))
        self.assertEqual(backoff_seconds(20), BACKOFF_CAP_SECONDS)

    def test_a_second_sync_request_reuses_ids(self):
        row = LocalRow("obs-7")
        remote = Remote()
        sync_once(row, remote)
        first_children = set(remote.children)
        sync_once(row, remote)
        self.assertEqual(remote.children, first_children)
        self.assertEqual(row.status, "synced")

    def test_several_pending_rows_survive_a_restart_and_a_child_repair(self):
        remote = Remote()
        rows = [LocalRow(f"obs-{i}") for i in range(3)]
        sync_once(rows[0], remote, network=False)
        remote.fail = "children"
        sync_once(rows[1], remote)
        self.assertEqual(rows[1].status, "failed")
        self.assertIn(rows[1].id, remote.observations)
        self.assertNotIn(stable_ids(rows[1].id)["detection"], remote.children)
        self.assertNotIn(rows[1].id, remote.receipts)
        remote.fail = None
        recover_stuck(rows)
        for row in rows:
            self.assertFalse(row.deleted)
            sync_once(row, remote)
        self.assertTrue(all(row.status == "synced" for row in rows))
        self.assertEqual(len(remote.observations), 3)
        self.assertEqual(len(remote.children), 6)
        sync_once(rows[1], remote)
        self.assertEqual(len(remote.children), 6)


if __name__ == "__main__":
    unittest.main()
