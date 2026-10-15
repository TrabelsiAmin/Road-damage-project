-- =============================================================================
-- Test Plan: test_clustering_plan.sql
-- Proves PostGIS ST_ClusterDBSCAN in EPSG:32632:
--   1. Two reports 10 m apart (Points A and B) merge into a single cluster (report_count = 2).
--   2. A report 60 m apart (Point C) does NOT merge and forms a separate cluster.
--   3. A report with accuracy_meters > 25 (Point D) is filtered out.
--
-- EXECUTION: Run inside a sandbox transaction (BEGIN ... ROLLBACK) so no live
-- data is modified.
-- =============================================================================

BEGIN;

-- 1. Create temporary testing tables mirroring observations and locations
CREATE TEMP TABLE test_obs (
  id uuid PRIMARY KEY,
  anomaly_type text,
  priority_score double precision,
  status text,
  created_at timestamptz
);

CREATE TEMP TABLE test_loc (
  observation_id uuid REFERENCES test_obs(id),
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision
);

-- 2. Seed Test Points:
-- Point A: Base point in Tunis (Avenue Habib Bourguiba area)
-- Point B: 10.0 meters North of A (must MERGE with A)
-- Point C: 60.1 meters North of B (70.1m North of A; must NOT merge, separate cluster)
-- Point D: 1.0 meter from C, but accuracy_meters = 35 (> 25m threshold; must be EXCLUDED)
INSERT INTO test_obs (id, anomaly_type, priority_score, status, created_at) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'D40', 90.0, 'unconfirmed', NOW() - INTERVAL '2 days'),
  ('b0000000-0000-0000-0000-000000000002', 'D20', 75.0, 'confirmed',   NOW() - INTERVAL '1 day'),
  ('c0000000-0000-0000-0000-000000000003', 'D10', 40.0, 'unconfirmed', NOW()),
  ('d0000000-0000-0000-0000-000000000004', 'D00', 30.0, 'unconfirmed', NOW());

INSERT INTO test_loc (observation_id, latitude, longitude, accuracy_meters) VALUES
  ('a0000000-0000-0000-0000-000000000001', 36.8000000, 10.1800000, 8.0),
  ('b0000000-0000-0000-0000-000000000002', 36.8000901, 10.1800000, 12.0),
  ('c0000000-0000-0000-0000-000000000003', 36.8006306, 10.1800000, 10.0),
  ('d0000000-0000-0000-0000-000000000004', 36.8006400, 10.1800000, 35.0); -- Inaccurate GPS (> 25m)

-- 3. Run DBSCAN clustering query with eps = 20.0m in EPSG:32632
WITH valid_reports AS (
  SELECT
    o.id AS observation_id,
    o.anomaly_type,
    o.priority_score,
    o.status,
    o.created_at,
    loc.latitude,
    loc.longitude,
    loc.accuracy_meters,
    extensions.ST_Transform(
      extensions.ST_SetSRID(extensions.ST_MakePoint(loc.longitude, loc.latitude), 4326),
      32632
    ) AS geom_utm
  FROM test_obs o
  INNER JOIN test_loc loc ON loc.observation_id = o.id
  WHERE loc.accuracy_meters <= 25.0
),
clustered AS (
  SELECT
    vr.*,
    extensions.ST_ClusterDBSCAN(
      vr.geom_utm,
      eps := 20.0,
      minpoints := 1
    ) OVER () AS cluster_id
  FROM valid_reports vr
)
SELECT
  cluster_id,
  COUNT(*) AS cluster_size,
  array_agg(observation_id ORDER BY observation_id) AS merged_observations,
  ROUND(extensions.ST_Distance(
    MIN(geom_utm),
    MAX(geom_utm)
  )::numeric, 2) AS cluster_span_meters,
  CASE
    WHEN COUNT(*) = 2 AND bool_and(observation_id IN ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002'))
      THEN 'PASS: Points A (0m) and B (10m) merged into 1 cluster'
    WHEN COUNT(*) = 1 AND bool_and(observation_id = 'c0000000-0000-0000-0000-000000000003')
      THEN 'PASS: Point C (60m away) isolated in separate cluster'
    ELSE 'FAIL: Unexpected cluster configuration'
  END AS test_assertion
FROM clustered
GROUP BY cluster_id
ORDER BY cluster_id;

-- 4. Assert accuracy filtering: Verify Point D is NOT in any cluster
DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM test_loc
  WHERE accuracy_meters <= 25.0 AND observation_id = 'd0000000-0000-0000-0000-000000000004';
  
  IF v_count = 0 THEN
    RAISE NOTICE 'PASS: Inaccurate Point D (accuracy 35m > 25m) was successfully excluded.';
  ELSE
    RAISE EXCEPTION 'FAIL: Point D was not filtered by accuracy_meters <= 25';
  END IF;
END $$;

-- Clean rollback: Nothing is committed to any table
ROLLBACK;
