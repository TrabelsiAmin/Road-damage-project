# Offline Persistence and Synchronization Design

## Local-first invariant

The observation is committed to local storage before the UI reports success. Inference and location are prerequisites for a complete observation, but synchronization is not. The local record contains an immutable capture payload plus mutable synchronization and review fields.

## Queue states

`pending → uploading → synced` is the normal path. Recoverable failures return to `pending` with `attemptCount`, `nextAttemptAt`, and `lastError`. Permanent validation failures become `needs_review`. Authentication failures pause the queue until the session is restored.

## Idempotency

The client generates `observationId` and sends it as both the resource ID and idempotency key. A retry of the same observation must not create a duplicate. The server stores a sync receipt containing client ID, server ID, payload hash, and first accepted timestamp.

## Conflict policy

The image and model detections are immutable evidence. Operator corrections, incident status, responsible owner, and notes are mutable fields. Server changes win for workflow state, while local edits are retained as a conflict event requiring review. No destructive merge is performed silently.

## Backoff

Retry after 30 seconds, then 2, 4, 8, and 16 minutes, with random jitter. Stop after a configurable maximum and surface a clear action in the sync screen. Wi-Fi-only upload is an explicit setting, not an assumption.

## Implementation recommendation

Use SQLite/Drift or Isar for production because observations, detections, queue state, and audit events are relational and query-heavy. Keep captured images in app-private files and reference them by path. Encrypt the database or sensitive columns where supported. Use a single repository interface so a test in-memory store can replace the device store.

## Recovery cases

The app must survive process termination during inference, upload, and file deletion. Mark `uploading` records as recoverable on startup. Never delete local evidence until the server acknowledges both observation metadata and attachment checksum. Provide a storage health screen showing count, bytes, oldest pending item, and failed items.


---

## Drive Awareness SQLite Anomaly Caching (Schema Version 4)

To ensure vehicle warnings work in zero-coverage zones and remote highways, road anomalies are persisted in a local `cached_anomalies` table.

### Schema Definition
```sql
CREATE TABLE IF NOT EXISTS cached_anomalies (
  observation_id   TEXT PRIMARY KEY,
  latitude         REAL NOT NULL,
  longitude        REAL NOT NULL,
  anomaly_type     TEXT NOT NULL,
  priority_score   REAL NOT NULL,
  priority_label   TEXT NOT NULL,
  status           TEXT NOT NULL,
  accuracy_meters  REAL,
  created_at       TEXT NOT NULL,
  report_count     INTEGER NOT NULL DEFAULT 1,
  cached_at        TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_cached_anomalies_coords
ON cached_anomalies (latitude, longitude);
```

### Cache Invariants & Eviction Policy
1. **TTL Expiration**: Records cached older than 24 hours (configurable) are automatically filtered out from nearby queries.
2. **LRU Size Capping**: If the table exceeds 500 records, the oldest entries (`ORDER BY cached_at ASC`) are automatically pruned.
3. **Spatial Radius Lookup**: Queries filter with a bounding box in SQLite first, followed by exact Haversine distance calculations.
