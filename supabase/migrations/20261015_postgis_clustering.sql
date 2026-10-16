-- =============================================================================
-- Migration: 20261015_postgis_clustering.sql
-- Phase 2: Geospatial Distance Clustering via PostGIS ST_ClusterDBSCAN
--
-- Specifications:
--   1. Work in projected CRS for Tunisia (EPSG:32632 - WGS 84 / UTM zone 32N).
--   2. Radius: 20 meters (eps := 20.0).
--   3. Filter: locations with accuracy_meters <= 25 only.
--   4. Aggregate per cluster:
--        - cluster_id (dense cluster identifier)
--        - centroid_lat / centroid_lng (projected centroid converted to WGS 84)
--        - report_count
--        - worst_class (D40 > D20 > D10 > D00)
--        - max_priority_score
--        - first_seen / last_seen
--        - status_counts (jsonb breakdown of unconfirmed, confirmed, repaired, etc.)
--   5. Privacy: Strictly DOES NOT expose device_id.
--   6. Grants: EXECUTE granted only to anon and authenticated.
-- =============================================================================

-- Ensure PostGIS extension is active
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

-- Function: public.get_clusters
CREATE OR REPLACE FUNCTION public.get_clusters(
  eps_meters double precision DEFAULT 20.0,
  min_points integer DEFAULT 1
)
RETURNS TABLE (
  cluster_id integer,
  centroid_lat double precision,
  centroid_lng double precision,
  report_count bigint,
  worst_class text,
  max_priority_score double precision,
  first_seen timestamptz,
  last_seen timestamptz,
  status_counts jsonb
)
LANGUAGE sql
STABLE
SET search_path = public, extensions, pg_temp
AS $$
  WITH valid_reports AS (
    -- 1. Select reports with accurate GPS coordinates (accuracy_meters <= 25)
    -- STRICT PRIVACY: device_id is never selected or referenced
    SELECT
      o.id AS observation_id,
      o.anomaly_type,
      o.priority_score,
      o.status,
      o.created_at,
      loc.latitude,
      loc.longitude,
      loc.accuracy_meters,
      -- Project WGS 84 (EPSG:4326) into Tunisia UTM Zone 32N (EPSG:32632, metric coordinates)
      extensions.ST_Transform(
        extensions.ST_SetSRID(extensions.ST_MakePoint(loc.longitude, loc.latitude), 4326),
        32632
      ) AS geom_utm
    FROM public.observations o
    INNER JOIN public.locations loc ON loc.observation_id = o.id
    WHERE loc.latitude IS NOT NULL
      AND loc.longitude IS NOT NULL
      AND loc.latitude BETWEEN -90.0 AND 90.0
      AND loc.longitude BETWEEN -180.0 AND 180.0
      AND loc.accuracy_meters <= 25.0
  ),
  clustered_points AS (
    -- 2. Run PostGIS DBSCAN metric clustering in EPSG:32632 (eps in meters)
    SELECT
      vr.*,
      extensions.ST_ClusterDBSCAN(
        vr.geom_utm,
        eps := eps_meters,
        minpoints := min_points
      ) OVER () AS dbscan_cid
    FROM valid_reports vr
  ),
  grouped_clusters AS (
    -- 3. Group by cluster id (assigning distinct negative IDs to unclustered noise if min_points > 1)
    SELECT
      COALESCE(
        cp.dbscan_cid,
        -1 * ROW_NUMBER() OVER (ORDER BY cp.created_at)
      ) AS raw_cluster_id,
      cp.*
    FROM clustered_points cp
  )
  -- 4. Aggregate metrics across all reports in each cluster
  SELECT
    DENSE_RANK() OVER (ORDER BY raw_cluster_id)::integer AS cluster_id,
    ROUND(
      extensions.ST_Y(
        extensions.ST_Transform(extensions.ST_Centroid(extensions.ST_Collect(geom_utm)), 4326)
      )::numeric,
      7
    )::double precision AS centroid_lat,
    ROUND(
      extensions.ST_X(
        extensions.ST_Transform(extensions.ST_Centroid(extensions.ST_Collect(geom_utm)), 4326)
      )::numeric,
      7
    )::double precision AS centroid_lng,
    COUNT(*)::bigint AS report_count,
    -- Dominant class according to severity hierarchy (D40 > D20 > D10 > D00)
    CASE
      WHEN bool_or(anomaly_type = 'D40') THEN 'D40'
      WHEN bool_or(anomaly_type = 'D20') THEN 'D20'
      WHEN bool_or(anomaly_type = 'D10') THEN 'D10'
      WHEN bool_or(anomaly_type = 'D00') THEN 'D00'
      ELSE COALESCE(MAX(anomaly_type), 'D40')
    END AS worst_class,
    ROUND(COALESCE(MAX(priority_score), 0.0)::numeric, 2)::double precision AS max_priority_score,
    MIN(created_at) AS first_seen,
    MAX(created_at) AS last_seen,
    jsonb_build_object(
      'unconfirmed', COUNT(*) FILTER (WHERE status = 'unconfirmed'),
      'confirmed',   COUNT(*) FILTER (WHERE status = 'confirmed'),
      'repaired',    COUNT(*) FILTER (WHERE status = 'repaired'),
      'in_progress', COUNT(*) FILTER (WHERE status = 'in_progress'),
      'rejected',    COUNT(*) FILTER (WHERE status = 'rejected')
    ) AS status_counts
  FROM grouped_clusters
  GROUP BY raw_cluster_id
  ORDER BY max_priority_score DESC, report_count DESC;
$$;

-- Standard view for direct client queries
CREATE OR REPLACE VIEW public.v_clusters AS
SELECT * FROM public.get_clusters(20.0, 1);

-- -----------------------------------------------------------------------------
-- Permissions: Grant execute only to anon and authenticated
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_clusters(double precision, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_clusters(double precision, integer) TO anon, authenticated;

REVOKE ALL ON public.v_clusters FROM PUBLIC;
GRANT SELECT ON public.v_clusters TO anon, authenticated;
