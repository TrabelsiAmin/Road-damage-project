-- =============================================================================
-- Migration: 20261102_drive_awareness_rpc.sql
-- Feature: Drive Awareness — Road Anomaly Spatial Discovery
--
-- Security & Performance Profile:
--   - Read-only spatial query using PostGIS ST_DWithin on locations.geog.
--   - Uses spatial GiST index for fast bounded bounding-box searches.
--   - Excludes rejected observations (status = 'rejected') and demo records.
--   - Excludes observations with poor accuracy (> 100m) or invalid coordinates.
--   - Bounded radius (50m to 5000m) and max results (1 to 200) to prevent denial of service.
--   - SECURITY INVOKER with fixed search_path = public, pg_temp.
--   - Does NOT expose device_id, private media URLs, or user credentials.
-- =============================================================================

-- 1. Ensure geography column and GiST index exist on public.locations
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'locations' 
      AND column_name = 'geog'
  ) THEN
    ALTER TABLE public.locations ADD COLUMN geog geography(Point, 4326);
  END IF;
END $$;

-- Populate geography for any existing records missing it
UPDATE public.locations
SET geog = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
WHERE geog IS NULL 
  AND latitude IS NOT NULL 
  AND longitude IS NOT NULL
  AND latitude BETWEEN -90.0 AND 90.0
  AND longitude BETWEEN -180.0 AND 180.0
  AND (latitude <> 0.0 OR longitude <> 0.0);

-- Create spatial GiST index if not already present
CREATE INDEX IF NOT EXISTS idx_locations_geog ON public.locations USING GIST (geog);

-- 2. Create get_nearby_anomalies RPC function
CREATE OR REPLACE FUNCTION public.get_nearby_anomalies(
  current_lat double precision,
  current_lng double precision,
  radius_meters double precision DEFAULT 1000.0,
  max_results integer DEFAULT 100
)
RETURNS TABLE (
  observation_id text,
  latitude double precision,
  longitude double precision,
  anomaly_type text,
  priority_score double precision,
  priority_label text,
  status text,
  accuracy_meters double precision,
  created_at timestamptz,
  report_count bigint,
  worst_class text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH safe_params AS (
    SELECT
      current_lat AS lat,
      current_lng AS lng,
      LEAST(GREATEST(COALESCE(radius_meters, 1000.0), 50.0), 5000.0) AS rad,
      LEAST(GREATEST(COALESCE(max_results, 100), 1), 200) AS lim,
      ST_SetSRID(ST_MakePoint(current_lng, current_lat), 4326)::geography AS center_geog
  ),
  candidates AS (
    SELECT
      o.id::text AS obs_id,
      l.latitude,
      l.longitude,
      COALESCE(o.anomaly_type, 'D00') AS a_type,
      ROUND(COALESCE(o.priority_score, 0)::numeric, 1)::double precision AS p_score,
      COALESCE(o.priority_label, 'LOW') AS p_label,
      COALESCE(o.status, 'unconfirmed') AS o_status,
      l.accuracy_meters::double precision AS acc_meters,
      o.created_at,
      ST_Distance(
        COALESCE(l.geog, ST_SetSRID(ST_MakePoint(l.longitude, l.latitude), 4326)::geography),
        sp.center_geog
      ) AS dist_meters
    FROM safe_params sp
    JOIN public.locations l ON ST_DWithin(
      COALESCE(l.geog, ST_SetSRID(ST_MakePoint(l.longitude, l.latitude), 4326)::geography),
      sp.center_geog,
      sp.rad
    )
    JOIN public.observations o ON o.id = l.observation_id
    WHERE l.latitude IS NOT NULL
      AND l.longitude IS NOT NULL
      AND l.latitude BETWEEN -90.0 AND 90.0
      AND l.longitude BETWEEN -180.0 AND 180.0
      AND (l.latitude <> 0.0 OR l.longitude <> 0.0)
      AND (l.accuracy_meters IS NULL OR l.accuracy_meters <= 100.0)
      AND o.status <> 'rejected'
      AND o.is_demo = false
  )
  SELECT
    c.obs_id AS observation_id,
    c.latitude,
    c.longitude,
    c.a_type AS anomaly_type,
    c.p_score AS priority_score,
    c.p_label AS priority_label,
    c.o_status AS status,
    c.acc_meters AS accuracy_meters,
    c.created_at,
    1::bigint AS report_count,
    c.a_type AS worst_class
  FROM candidates c
  ORDER BY c.dist_meters ASC, c.p_score DESC
  LIMIT (SELECT lim FROM safe_params);
$$;

-- 3. Grants
REVOKE ALL ON FUNCTION public.get_nearby_anomalies(double precision, double precision, double precision, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_nearby_anomalies(double precision, double precision, double precision, integer) TO anon, authenticated;

COMMENT ON FUNCTION public.get_nearby_anomalies IS 
  'Drive Awareness read-only query: returns non-rejected road anomalies within radius_meters of (current_lat, current_lng) ordered by proximity and priority.';
