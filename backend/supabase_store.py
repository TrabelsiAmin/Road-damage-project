"""Supabase persistence for the TariqMap backend.

The backend uses the Supabase REST API rather than exposing database credentials
or requiring a database driver. The service-role key is read only from the
process environment and is never stored in source control.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import uuid
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote

import httpx
from dotenv import load_dotenv

from schemas import ObservationUpload

load_dotenv()

_JWT_RE = re.compile(r"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+")


def redact_secrets(text: str) -> str:
    """Strip JWT-shaped tokens before a message is logged or returned."""
    return _JWT_RE.sub("[redacted]", text)


class SupabaseNotConfigured(RuntimeError):
    """Raised when the backend has not been given its Supabase credentials."""


class SupabaseStore:
    def __init__(self) -> None:
        self.url = os.environ.get(
            "TARIQMAP_SUPABASE_URL",
            "https://lendqcjihusqkmxansbl.supabase.co",
        ).rstrip("/")
        self.key = os.environ.get("TARIQMAP_SUPABASE_SERVICE_ROLE_KEY") or os.environ.get(
            "SUPABASE_SERVICE_ROLE_KEY"
        )
        self.organization_ids = {
            "Municipality": "11111111-1111-4111-8111-111111111111",
            "Ministry of Equipment": "22222222-2222-4222-8222-222222222222",
            "Tunisia Autoroutes": "33333333-3333-4333-8333-333333333333",
        }
        self.timeout = httpx.Timeout(20.0, connect=5.0)

    @property
    def configured(self) -> bool:
        return bool(self.key)

    def _headers(self, *, prefer: str | None = None) -> dict[str, str]:
        if not self.key:
            raise SupabaseNotConfigured(
                "Set TARIQMAP_SUPABASE_SERVICE_ROLE_KEY before starting the backend."
            )
        headers = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": "application/json",
        }
        if prefer:
            headers["Prefer"] = prefer
        return headers

    def _request(
        self,
        method: str,
        table: str,
        *,
        params: dict[str, str] | None = None,
        payload: Any = None,
        prefer: str | None = None,
    ) -> httpx.Response:
        response = httpx.request(
            method,
            f"{self.url}/rest/v1/{table}",
            headers=self._headers(prefer=prefer),
            params=params,
            json=payload,
            timeout=self.timeout,
        )
        if response.status_code >= 400:
            detail = redact_secrets(response.text[:1000])
            raise RuntimeError(f"Supabase {method} {table} failed ({response.status_code}): {detail}")
        return response

    @staticmethod
    def _timestamp(value: str | None) -> str:
        if not value:
            return datetime.now(timezone.utc).isoformat()
        return value

    def _organization_id(self, actor: str) -> str:
        return self.organization_ids.get(actor, self.organization_ids["Municipality"])

    def _existing_receipt(self, observation_id: str) -> bool:
        response = self._request(
            "GET",
            "sync_receipts",
            params={"observation_id": f"eq.{observation_id}", "select": "observation_id", "limit": "1"},
        )
        return bool(response.json())

    def _row_exists(self, table: str, row_id: str) -> bool:
        response = self._request(
            "GET",
            table,
            params={"id": f"eq.{quote(row_id, safe='')}", "select": "id", "limit": "1"},
        )
        return bool(response.json())

    def _has_value(self, table: str, column: str, value: str) -> bool:
        response = self._request(
            "GET",
            table,
            params={column: f"eq.{quote(value, safe='')}", "select": column, "limit": "1"},
        )
        return bool(response.json())

    def _ids_for_observation(self, table: str, observation_id: str) -> set[str]:
        response = self._request(
            "GET",
            table,
            params={
                "observation_id": f"eq.{quote(observation_id, safe='')}",
                "select": "id",
                "limit": "1000",
            },
        )
        return {row["id"] for row in response.json() if row.get("id")}

    def insert_observation(self, body: ObservationUpload, idempotency_key: str) -> dict[str, str]:
        """Insert an observation and only the child rows whose stable ids are absent.

        Media bytes are uploaded by the mobile client, not by this method.
        A receipt is written only after the observation, location, agent runs,
        and detections for this payload are present. A network or auth error
        from `_request` is not turned into already_received.

        Schema limit: a child written earlier with a random id is not deleted.
        This method only recognizes the UUID v5 ids derived from the local
        observation id. A second random row can therefore remain.
        """
        captured_at = self._timestamp(body.createdAt)
        organization_id = body.organizationId or self._organization_id(body.actor)
        inserted_any = False
        observation_was_new = False

        if not self._row_exists("observations", body.id):
            observation_was_new = True
            observation = {
                "id": body.id,
                "capture_id": body.captureId,
                "parent_observation_id": None,
                "created_by": None,
                "organization_id": organization_id,
                "device_id": body.deviceId,
                "source": "camera",
                "captured_at": captured_at,
                "image_width": body.imageWidth,
                "image_height": body.imageHeight,
                "priority_score": body.priorityScore,
                "priority_label": body.priorityLabel,
                "model_bundle_version": body.modelBundleVersion,
                "created_at": captured_at,
            }
            self._request("POST", "observations", payload=observation, prefer="return=minimal")
            inserted_any = True

        if not self._has_value("locations", "observation_id", body.id):
            location = {
                "observation_id": body.id,
                "latitude": body.latitude,
                "longitude": body.longitude,
                "accuracy_meters": body.accuracyMeters,
                "captured_at": captured_at,
            }
            self._request("POST", "locations", payload=location, prefer="return=minimal")
            inserted_any = True

        existing_runs = self._ids_for_observation("agent_runs", body.id)
        existing_detections = self._ids_for_observation("detections", body.id)
        for index, result in enumerate(body.agentResults):
            agent_run_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{body.id}:agent:{index}:{result.agent}"))
            if agent_run_id not in existing_runs:
                agent_run = {
                    "id": agent_run_id,
                    "observation_id": body.id,
                    "agent": result.agent,
                    "error": result.error,
                    "is_mock": result.isMock,
                    "latency_ms": result.latencyMs,
                    "model_bundle_version": body.modelBundleVersion,
                }
                self._request("POST", "agent_runs", payload=agent_run, prefer="return=minimal")
                inserted_any = True

            missing = []
            for det_index, detection in enumerate(result.detections):
                detection_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{body.id}:det:{index}:{det_index}"))
                if detection_id in existing_detections:
                    continue
                missing.append(
                    {
                        "id": detection_id,
                        "observation_id": body.id,
                        "agent_run_id": agent_run_id,
                        "media_id": None,
                        "class_code": detection.classCode,
                        "confidence": detection.confidence,
                        "box_x": detection.box.x,
                        "box_y": detection.box.y,
                        "box_w": detection.box.width,
                        "box_h": detection.box.height,
                        "frame_index": detection.frameIndex,
                        "is_mock": result.isMock,
                        "model_bundle_version": detection.modelBundleVersion or body.modelBundleVersion,
                        "detected_at": detection.timestamp or captured_at,
                    }
                )
            if missing:
                self._request("POST", "detections", payload=missing, prefer="return=minimal")
                inserted_any = True

        if not self._existing_receipt(body.id):
            try:
                receipt_uuid = str(uuid.UUID(idempotency_key))
            except ValueError:
                receipt_uuid = str(uuid.uuid5(uuid.NAMESPACE_URL, idempotency_key))
            payload_hash = hashlib.sha256(
                json.dumps(body.model_dump(mode="json"), sort_keys=True, separators=(",", ":")).encode()
            ).hexdigest()
            receipt = {
                "observation_id": body.id,
                "idempotency_key": receipt_uuid,
                "payload_hash": payload_hash,
            }
            self._request("POST", "sync_receipts", payload=receipt, prefer="return=minimal")
            inserted_any = True

        if observation_was_new:
            status = "created"
        elif inserted_any:
            status = "repaired"
        else:
            status = "already_received"
        return {"status": status, "id": body.id}

    def list_observations(self, actor: str | None, limit: int) -> list[dict[str, Any]]:
        params = {
            "select": "id,capture_id,organization_id,source,captured_at,priority_score,priority_label,model_bundle_version,created_at",
            "order": "created_at.desc",
            "limit": str(max(1, min(limit, 1000))),
        }
        if actor:
            params["organization_id"] = f"eq.{self._organization_id(actor)}"
        return self._request("GET", "observations", params=params).json()

    def get_observation(self, observation_id: str) -> dict[str, Any] | None:
        params = {
            "id": f"eq.{quote(observation_id, safe='')}",
            "select": "id,capture_id,parent_observation_id,created_by,organization_id,source,captured_at,image_width,image_height,priority_score,priority_label,anomaly_type,model_bundle_version,created_at,synced_at,is_demo,status,assigned_contractor,budget_estimate_tnd",
            "limit": "1",
        }
        rows = self._request("GET", "observations", params=params).json()
        if not rows:
            return None
        observation = rows[0]
        observation["locations"] = self._request(
            "GET", "locations", params={"observation_id": f"eq.{observation_id}", "select": "*", "limit": "1"}
        ).json()
        observation["agent_runs"] = self._request(
            "GET", "agent_runs", params={"observation_id": f"eq.{observation_id}", "select": "*", "limit": "100"}
        ).json()
        observation["detections"] = self._request(
            "GET", "detections", params={"observation_id": f"eq.{observation_id}", "select": "*", "limit": "1000"}
        ).json()
        return observation

    def stats(self) -> dict[str, Any]:
        observations = self._request(
            "GET", "observations", params={"select": "id,organization_id,priority_label", "limit": "1000"}
        ).json()
        detections = self._request(
            "GET", "detections", params={"select": "class_code", "limit": "5000"}
        ).json()
        by_actor: dict[str, int] = {}
        organization_names = {value: key for key, value in self.organization_ids.items()}
        by_priority = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0}
        for observation in observations:
            actor = organization_names.get(observation.get("organization_id"), "Unknown")
            by_actor[actor] = by_actor.get(actor, 0) + 1
            label = observation.get("priority_label")
            if label:
                by_priority[label] = by_priority.get(label, 0) + 1
        by_class: dict[str, int] = {}
        for detection in detections:
            raw = detection.get("class_code")
            if raw is None or not str(raw).strip():
                continue
            code = str(raw).strip()
            by_class[code] = by_class.get(code, 0) + 1
        return {
            "total": len(observations),
            "by_actor": by_actor,
            "by_priority": by_priority,
            "by_class": by_class,
        }

    def health_count(self) -> int:
        response = self._request(
            "GET",
            "observations",
            params={"select": "id", "limit": "1"},
            prefer="count=exact",
        )
        content_range = response.headers.get("content-range", "*/0")
        try:
            return int(content_range.rsplit("/", 1)[1])
        except (ValueError, IndexError):
            return 0
