"""Validation tests that never call Supabase.

These hit FastAPI request validation and the redaction helper only.
They do not call /v1/health, /v1/observations list, or any route that
reads the service-role key.
"""
from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

from fastapi.testclient import TestClient  # noqa: E402

from main import app  # noqa: E402
from supabase_store import redact_secrets  # noqa: E402


def _valid_body() -> dict:
    return {
        "id": "obs-local-1",
        "captureId": "cap-local-1",
        "imagePath": "local.jpg",
        "createdAt": "2026-11-05T00:00:00Z",
        "latitude": 36.8,
        "longitude": 10.18,
        "actor": "Municipality",
        "agentResults": [],
    }


class ApiValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)

    def test_rejects_latitude_out_of_range(self) -> None:
        body = _valid_body()
        body["latitude"] = 999
        response = self.client.post("/v1/observations", json=body)
        self.assertEqual(response.status_code, 422)

    def test_rejects_empty_id(self) -> None:
        body = _valid_body()
        body["id"] = ""
        response = self.client.post("/v1/observations", json=body)
        self.assertEqual(response.status_code, 422)

    def test_rejects_limit_zero(self) -> None:
        response = self.client.get("/v1/observations", params={"limit": 0})
        self.assertEqual(response.status_code, 422)

    def test_rejects_short_detect_payload(self) -> None:
        response = self.client.post("/v1/detect", json={"image_b64": "abc"})
        self.assertEqual(response.status_code, 422)
        self.assertNotIn("abc", response.text)
        self.assertEqual(response.json()["detail"][0]["input"], "[redacted]")
        self.assertIn("image_b64", response.json()["detail"][0]["loc"])

    def test_store_error_does_not_echo_token_text(self) -> None:
        token = (
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            "eyJyb2xlIjoidGVzdCJ9."
            "c2lnbmF0dXJl"
        )

        def _boom(*_args, **_kwargs):
            raise RuntimeError(f"upstream said {token}")

        from main import store

        previous = store.insert_observation
        store.insert_observation = _boom
        try:
            response = self.client.post("/v1/observations", json=_valid_body())
        finally:
            store.insert_observation = previous
        self.assertEqual(response.status_code, 502)
        self.assertEqual(response.json()["detail"], "The observation store rejected the request")
        self.assertNotIn("eyJ", response.text)
        self.assertNotIn(token, response.text)

    def test_redact_secrets_strips_jwt_shape(self) -> None:
        raw = "failed eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidGVzdCJ9.c2lnbmF0dXJl tail"
        cleaned = redact_secrets(raw)
        self.assertNotIn("eyJ", cleaned)
        self.assertIn("[redacted]", cleaned)
        self.assertIn("tail", cleaned)


if __name__ == "__main__":
    unittest.main()
