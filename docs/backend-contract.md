# Backend Contract

The mobile client is offline-first, but a shared backend is required for institutional dashboards, synchronization, road-network matching, and auditability.

## API conventions

All requests use HTTPS and include `X-Client-Version`, `X-Model-Bundle`, and an idempotency key for mutations. JSON timestamps are UTC ISO-8601. IDs are UUIDs. A mutation returns the canonical server resource, not only a status message.

### Create or synchronize an observation

`POST /v1/observations`

```json
{
  "id": "client-generated-uuid",
  "captureId": "capture-uuid",
  "capturedAt": "2026-09-15T17:00:00Z",
  "actor": "municipality",
  "location": {"latitude": 36.8065, "longitude": 10.1815, "accuracyMeters": 7.4},
  "image": {"sha256": "...", "contentType": "image/jpeg"},
  "modelBundle": "2026.09.0",
  "detections": [
    {"agent": "pavement", "classCode": "D40", "confidence": 0.91,
     "box": {"x": 0.2, "y": 0.3, "width": 0.4, "height": 0.2}}
  ],
  "agentErrors": []
}
```

The server validates schema, ownership permissions, confidence ranges, model compatibility, and image checksum. Repeating the same client ID returns the existing canonical observation.

### Match a road

`GET /v1/roads/match?latitude=36.8065&longitude=10.1815`

Response:

```json
{
  "routeId": "route-123",
  "routeName": "A1",
  "segmentId": "segment-456",
  "owner": "tunisia_autoroutes",
  "distanceMeters": 3.8,
  "matchQuality": "high"
}
```

A low-quality or missing match must be represented as `unmatched`, never guessed silently.

### Incidents

- `POST /v1/incidents` creates a confirmed incident from an observation.
- `GET /v1/incidents?actor=&status=&bbox=` filters a workspace.
- `PATCH /v1/incidents/{id}` applies a validated status transition.
- `GET /v1/incidents/{id}/timeline` returns the audit trail.

## Relational model

The minimum schema contains `users`, `workspaces`, `workspace_members`, `observations`, `detections`, `road_segments`, `incidents`, `incident_events`, `attachments`, and `sync_receipts`. Spatial columns should use PostGIS or a compatible geospatial index. `incident_events` is append-only.

## Security

Use short-lived access tokens with refresh rotation. Enforce workspace and actor authorization on every read and write. Store images privately. Generate short-lived signed download URLs only after authorization. Strip unnecessary EXIF data after extracting capture metadata. Rate-limit uploads, validate MIME type and file size, and scan attachments. Never accept a client-supplied owner without retaining the server’s matching evidence.

## Observability

Emit structured events for capture, inference completion, model error, queue retry, upload result, SIG match, incident transition, and user correction. Attach correlation IDs across mobile and backend. Metrics should include inference duration per agent, p50/p95 sync latency, agent failure rate, unmatched-road rate, duplicate mutation rate, and operator correction rate.


---

## Ministry Command Center PostGIS Contracts

### 1. PostGIS RPC: `get_road_segment_risk`
`POST /rest/v1/rpc/get_road_segment_risk`

Aggregates observations across spatial road corridors (`road_segments`) and computes composite risk scores, dominant defect classes, backlog age, and estimated repair budgets.

#### Parameters
| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `min_risk_level` | `text` | `'ALL'` | Minimum risk filter (`'ALL'`, `'CRITICAL'`, `'HIGH'`, `'MEDIUM'`, `'LOW'`) |

#### Return Schema
| Column | Type | Description |
| :--- | :--- | :--- |
| `segment_id` | `uuid` | Unique identifier of the corridor segment |
| `road_code` | `text` | Corridor identifier (`A1`, `A4`, `RN1`, `RN8`, etc.) |
| `road_name` | `text` | Formal corridor designation |
| `governorate` | `text` | Tunisian governorate name |
| `municipality` | `text` | Municipality / delegation name |
| `total_reports` | `integer` | Count of observations on corridor |
| `active_reports` | `integer` | Count of un-repaired anomalies |
| `dominant_class` | `text` | Dominant defect class (`D00`, `D10`, `D20`, `D40`) |
| `pothole_count` | `integer` | Count of severe D40 potholes |
| `max_priority_score` | `double precision` | Maximum priority score observed [0, 100] |
| `oldest_age_days` | `integer` | Age in days of oldest unresolved defect |
| `risk_score` | `double precision` | Composite risk score [0, 100] |
| `risk_level` | `text` | Categorical danger rating (`CRITICAL`, `HIGH`, `MEDIUM`, `LOW`) |
| `estimated_budget_tnd` | `double precision` | Estimated repair cost in Tunisian Dinars |

---

### 2. PostGIS RPC: `get_anomalies_in_bounds`
`POST /rest/v1/rpc/get_anomalies_in_bounds`

Enables debounced visible-bounds viewport querying on the GIS Operations Map, preventing full database loading in the browser.

#### Parameters
| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `min_lat` | `double precision` | *required* | Viewport south latitude |
| `min_lng` | `double precision` | *required* | Viewport west longitude |
| `max_lat` | `double precision` | *required* | Viewport north latitude |
| `max_lng` | `double precision` | *required* | Viewport east longitude |
| `status_filter` | `text` | `'all'` | Lifecycle status filter |
| `class_filter` | `text` | `'all'` | Damage class filter |
| `priority_filter` | `text` | `'all'` | Priority level filter |
| `include_demo` | `boolean` | `false` | Whether to include synthetic test data |
| `limit_count` | `integer` | `500` | Maximum markers returned |

---

### 3. Maintenance Schema

#### `maintenance_cases`
Tracks institutional case assignments, SLA due dates, contractor accountability, and repair notes:
- `id`: UUID (Primary Key)
- `observation_id`: UUID (Foreign Key -> `observations.id`, Unique)
- `case_number`: Text (`CASE-YYYY-XXXXXX`)
- `assigned_contractor_id`: UUID (Foreign Key -> `organizations.id`)
- `due_date`: Date
- `repair_notes`: Text
- `verified_at`: Timestamptz
- `verified_by`: UUID (Foreign Key -> `auth.users.id`)

#### `maintenance_events`
Append-only immutable audit trail capturing every decision made by ministry and municipal authorities:
- `id`: UUID (Primary Key)
- `observation_id`: UUID (Foreign Key -> `observations.id`)
- `user_id`: UUID (Foreign Key -> `auth.users.id`)
- `actor_email`: Text
- `action`: Text (`validation`, `assignment`, `status_change`, `rejection`, `repair_verify`, `model_feedback`)
- `previous_value`: Text
- `new_value`: Text
- `notes`: Text
- `created_at`: Timestamptz (Default `clock_timestamp()`)

---

## Drive Awareness PostGIS Contract

### PostGIS RPC: `get_nearby_anomalies`
`POST /rest/v1/rpc/get_nearby_anomalies` (or Supabase SDK `client.rpc('get_nearby_anomalies', ...)`)

Provides fast, spatially-indexed road anomaly lookups for the vehicle Drive Awareness subsystem using PostGIS `ST_DWithin`.

#### Parameters
| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `user_lat` | `double precision` | *required* | Current vehicle GPS latitude |
| `user_lon` | `double precision` | *required* | Current vehicle GPS longitude |
| `radius_meters` | `double precision` | `1000.0` | Search radius in meters (clamped 50.0 to 5000.0) |
| `max_results` | `integer` | `50` | Maximum candidate anomalies returned (clamped 1 to 200) |

#### Return Schema
| Column | Type | Description |
| :--- | :--- | :--- |
| `observation_id` | `uuid` | Unique identifier of the underlying observation |
| `latitude` | `double precision` | Anomaly latitude coordinate (WGS84) |
| `longitude` | `double precision` | Anomaly longitude coordinate (WGS84) |
| `distance_meters` | `double precision` | Great-circle distance to the anomaly in meters |
| `anomaly_type` | `text` | Defect class code (`D00`, `D10`, `D20`, `D40`) |
| `priority_score` | `double precision` | Composite severity score (0.0 to 100.0) |
| `priority_label` | `text` | Severity priority (`low`, `medium`, `high`, `critical`) |
| `status` | `text` | Observation lifecycle status (`unconfirmed`, `confirmed`, `repaired`) |
| `accuracy_meters` | `double precision` | Original capture GPS accuracy |
| `created_at` | `timestamptz` | UTC timestamp of observation |
| `report_count` | `bigint` | Cluster consensus / report count |

#### Spatial Indexing & Security
- Leverages spatial GiST index on `locations.geog` (`ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography`).
- Executable by `anon` and `authenticated` roles with `SECURITY DEFINER` and fixed `search_path = public, extensions`.
- Excludes rejected observations and demo synthetic data.
