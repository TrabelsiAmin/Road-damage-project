-- Phase 2: distance-based clustering (PostGIS lives in schema public on this project).
CREATE OR REPLACE FUNCTION public.get_clusters(
  eps_meters double precision DEFAULT 20.0,
  min_points integer DEFAULT 1
)
RETURNS TABLE (
  cluster_id integer,
  centroid_lat double precision,
  centroid_lng double precision,
  report_count bigint,
  real_count bigint,
  demo_count bigint,
  worst_class text,
  max_priority_score double precision,
  first_seen timestamptz,
  last_seen timestamptz,
  status_counts jsonb
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH valid_reports AS (
    SELECT o.id, o.anomaly_type, o.priority_score, o.status, o.created_at, o.is_demo,
           ST_Transform(ST_SetSRID(ST_MakePoint(l.longitude, l.latitude), 4326), 32632) AS g
    FROM public.observations o
    JOIN public.locations l ON l.observation_id = o.id
    WHERE l.latitude IS NOT NULL AND l.longitude IS NOT NULL
      AND l.accuracy_meters <= 25.0
  ),
  clustered AS (
    SELECT v.*, ST_ClusterDBSCAN(v.g, eps := eps_meters, minpoints := min_points) OVER () AS cid
    FROM valid_reports v
  ),
  labelled AS (
    SELECT c.*, COALESCE(c.cid, -1 * ROW_NUMBER() OVER (ORDER BY c.created_at, c.id)::int) AS raw_cid
    FROM clustered c
  )
  SELECT
    DENSE_RANK() OVER (ORDER BY raw_cid)::integer,
    ROUND(ST_Y(ST_Transform(ST_Centroid(ST_Collect(g)), 4326))::numeric, 7)::double precision,
    ROUND(ST_X(ST_Transform(ST_Centroid(ST_Collect(g)), 4326))::numeric, 7)::double precision,
    COUNT(*)::bigint,
    COUNT(*) FILTER (WHERE NOT is_demo)::bigint,
    COUNT(*) FILTER (WHERE is_demo)::bigint,
    CASE WHEN bool_or(anomaly_type = 'D40') THEN 'D40'
         WHEN bool_or(anomaly_type = 'D20') THEN 'D20'
         WHEN bool_or(anomaly_type = 'D10') THEN 'D10'
         WHEN bool_or(anomaly_type = 'D00') THEN 'D00'
         ELSE NULL END,
    ROUND(COALESCE(MAX(priority_score), 0)::numeric, 2)::double precision,
    MIN(created_at),
    MAX(created_at),
    jsonb_build_object(
      'unconfirmed', COUNT(*) FILTER (WHERE status = 'unconfirmed'),
      'confirmed',   COUNT(*) FILTER (WHERE status = 'confirmed'),
      'in_progress', COUNT(*) FILTER (WHERE status = 'in_progress'),
      'repaired',    COUNT(*) FILTER (WHERE status = 'repaired'),
      'rejected',    COUNT(*) FILTER (WHERE status = 'rejected'))
  FROM labelled
  GROUP BY raw_cid
  ORDER BY 8 DESC, 4 DESC;
$$;

CREATE OR REPLACE VIEW public.v_clusters WITH (security_invoker = true) AS
  SELECT * FROM public.get_clusters(20.0, 1);

REVOKE ALL ON FUNCTION public.get_clusters(double precision, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_clusters(double precision, integer) TO anon, authenticated;
REVOKE ALL ON public.v_clusters FROM PUBLIC;
GRANT SELECT ON public.v_clusters TO anon, authenticated;