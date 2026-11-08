"""Read-only duplicate report.

Confirmed means the same id appears twice, or two rows share a primary id.
Possible means different ids that share a capture, a location and time, or the
same observation plus the same agent or class fields. Nothing is deleted.
"""
from __future__ import annotations

from datetime import datetime


def _time(value: str | None):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def classify_duplicates(
    observations: list[dict],
    agent_runs: list[dict],
    detections: list[dict],
) -> dict:
    confirmed: list[dict] = []
    possible: list[dict] = []

    def same_id(rows: list[dict], kind: str) -> None:
        seen: dict[str, int] = {}
        for row in rows:
            row_id = row.get("id")
            if not row_id:
                continue
            seen[row_id] = seen.get(row_id, 0) + 1
        for row_id, count in seen.items():
            if count > 1:
                confirmed.append({"kind": kind, "id": row_id, "copies": count})

    same_id(observations, "observation")
    same_id(agent_runs, "agent_run")
    same_id(detections, "detection")

    by_capture: dict[str, list[str]] = {}
    for obs in observations:
        capture = obs.get("capture_id")
        obs_id = obs.get("id")
        if capture and obs_id:
            by_capture.setdefault(capture, [])
            if obs_id not in by_capture[capture]:
                by_capture[capture].append(obs_id)
    for capture, ids in by_capture.items():
        if len(ids) > 1:
            possible.append({"kind": "observation_capture", "capture_id": capture, "ids": ids})

    located = [obs for obs in observations if obs.get("id") and obs.get("latitude") is not None]
    for index, left in enumerate(located):
        left_time = _time(left.get("captured_at") or left.get("created_at"))
        for right in located[index + 1 :]:
            if left["id"] == right["id"]:
                continue
            if abs(float(left["latitude"]) - float(right["latitude"])) > 0.00001:
                continue
            if abs(float(left["longitude"]) - float(right["longitude"])) > 0.00001:
                continue
            right_time = _time(right.get("captured_at") or right.get("created_at"))
            if left_time and right_time and abs((left_time - right_time).total_seconds()) > 120:
                continue
            if left.get("anomaly_type") != right.get("anomaly_type"):
                continue
            possible.append(
                {
                    "kind": "observation_place_time",
                    "ids": [left["id"], right["id"]],
                }
            )

    runs_by_obs: dict[str, list[dict]] = {}
    for run in agent_runs:
        obs_id = run.get("observation_id")
        if obs_id:
            runs_by_obs.setdefault(obs_id, []).append(run)
    for obs_id, runs in runs_by_obs.items():
        by_agent: dict[str, list[str]] = {}
        for run in runs:
            agent = run.get("agent") or ""
            run_id = run.get("id")
            if not run_id:
                continue
            by_agent.setdefault(agent, [])
            if run_id not in by_agent[agent]:
                by_agent[agent].append(run_id)
        for agent, ids in by_agent.items():
            if len(ids) > 1:
                possible.append(
                    {"kind": "agent_run_same_agent", "observation_id": obs_id, "agent": agent, "ids": ids}
                )

    dets_by_obs: dict[str, list[dict]] = {}
    for det in detections:
        obs_id = det.get("observation_id")
        if obs_id:
            dets_by_obs.setdefault(obs_id, []).append(det)
    for obs_id, dets in dets_by_obs.items():
        by_slot: dict[tuple, list[str]] = {}
        for det in dets:
            slot = (det.get("class_code"), det.get("box_x"), det.get("box_y"), det.get("box_w"), det.get("box_h"))
            det_id = det.get("id")
            if not det_id:
                continue
            by_slot.setdefault(slot, [])
            if det_id not in by_slot[slot]:
                by_slot[slot].append(det_id)
        for slot, ids in by_slot.items():
            if len(ids) > 1:
                possible.append(
                    {
                        "kind": "detection_same_box",
                        "observation_id": obs_id,
                        "class_code": slot[0],
                        "ids": ids,
                    }
                )

    return {
        "confirmed": confirmed,
        "possible": possible,
        "deleted": 0,
        "merged": 0,
    }
