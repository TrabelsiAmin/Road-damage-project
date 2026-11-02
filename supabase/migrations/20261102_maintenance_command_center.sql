-- =============================================================================
-- Migration: 20261102_maintenance_command_center.sql
-- Feature: Ministry Road-Maintenance Command Center
--
-- Objectives:
--   1. Create maintenance_cases table for tracking lifecycle, assignments, due dates, and verification.
--   2. Create maintenance_events table for auditable operational history.
--   3. Create road_segments table for corridor risk modeling with canonical Tunisian corridors.
--   4. Implement PostGIS server-side functions:
--      - get_road_segment_risk(min_risk_level)
--      - get_command_center_kpis(...)
--      - get_anomalies_in_bounds(...)
--   5. Configure Row Level Security (RLS) and grant appropriate permissions.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Road Segments & Corridors Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.road_segments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,                       -- e.g. 'RN1-BEN_AROUS', 'A1-TUNIS-SOUSSE'
  name TEXT NOT NULL,                              -- e.g. 'Route Nationale 1 (Tunis - Ben Arous)'
  road_type TEXT NOT NULL DEFAULT 'NATIONAL',      -- 'AUTOROUTE', 'NATIONAL', 'REGIONAL', 'MUNICIPAL'
  governorate TEXT NOT NULL DEFAULT 'Tunis',
  municipality TEXT,
  importance_weight NUMERIC(3, 2) NOT NULL DEFAULT 1.0, -- 1.5 for Autoroute, 1.3 for RN, 1.0 for Regional, 0.8 for Municipal
  speed_limit_kmh INTEGER NOT NULL DEFAULT 90,
  centroid_lat DOUBLE PRECISION,
  centroid_lng DOUBLE PRECISION,
  geom GEOMETRY(LineString, 4326),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Spatial index on road_segments
CREATE INDEX IF NOT EXISTS idx_road_segments_geom ON public.road_segments USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_road_segments_gov ON public.road_segments (governorate);

-- Seed canonical Tunisian road corridors if missing
INSERT INTO public.road_segments (code, name, road_type, governorate, municipality, importance_weight, speed_limit_kmh, centroid_lat, centroid_lng)
VALUES
  ('RN1-TUNIS-SUD', 'Route Nationale 1 (Tunis Sud - Ben Arous)', 'NATIONAL', 'Ben Arous', 'Megrine', 1.30, 90, 36.7532, 10.2285),
  ('RN8-ARIANA', 'Route Nationale 8 (Tunis - Ariana - Bizerte)', 'NATIONAL', 'Ariana', 'Ariana Ville', 1.30, 90, 36.8665, 10.1956),
  ('RN9-MARSA', 'Route Nationale 9 (Tunis Centre - La Marsa)', 'NATIONAL', 'Tunis', 'La Marsa', 1.30, 90, 36.8512, 10.2854),
  ('A1-TUNIS-HAMMAMET', 'Autoroute A1 (Tunis - Mornag - Hammamet)', 'AUTOROUTE', 'Ben Arous', 'Mornag', 1.50, 110, 36.6800, 10.3000),
  ('A4-TUNIS-BIZERTE', 'Autoroute A4 (Tunis - Utique - Bizerte)', 'AUTOROUTE', 'Ariana', 'Kalaat el-Andalous', 1.50, 110, 36.9500, 10.1000),
  ('RR21-VOIE-X', 'Route Régionale 21 / Voie Express X (Grand Tunis)', 'REGIONAL', 'Tunis', 'El Menzah', 1.10, 70, 36.8320, 10.1540),
  ('RR23-GAMMARTH', 'Route Régionale 23 (La Marsa - Gammarth)', 'REGIONAL', 'Tunis', 'La Marsa', 1.00, 60, 36.8950, 10.2900),
  ('MUN-TUNIS-CENTRE', 'Voirie Urbaine Tunis Centre (Av. Habib Bourguiba)', 'MUNICIPAL', 'Tunis', 'Tunis Ville', 0.90, 50, 36.8000, 10.1800),
  ('MUN-ARIANA-SOUKRA', 'Voirie Urbaine La Soukra (Av. Fattouma Bourguiba)', 'MUNICIPAL', 'Ariana', 'La Soukra', 0.85, 50, 36.8750, 10.2400),
  ('MUN-RADES-PORT', 'Axe Portuaire Rades (Zone Logistique & Port)', 'MUNICIPAL', 'Ben Arous', 'Rades', 1.20, 60, 36.7700, 10.2750),
  ('RN3-MANOUBA', 'Route Nationale 3 (Tunis - Denden - Manouba)', 'NATIONAL', 'Manouba', 'Manouba Ville', 1.25, 80, 36.8080, 10.0900),
  ('A1-SOUSSE-NORD', 'Autoroute A1 (Enfidha - Sousse Nord)', 'AUTOROUTE', 'Sousse', 'Hammam Sousse', 1.50, 110, 35.8800, 10.5800)
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    importance_weight = EXCLUDED.importance_weight,
    centroid_lat = EXCLUDED.centroid_lat,
    centroid_lng = EXCLUDED.centroid_lng;

-- -----------------------------------------------------------------------------
-- 2. Maintenance Cases Table (Lifecycle, Assignment, Cost, Verification)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.maintenance_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  observation_id TEXT NOT NULL REFERENCES public.observations(id) ON DELETE CASCADE UNIQUE,
  case_number TEXT UNIQUE NOT NULL,
  assigned_to TEXT,                                  -- Contractor or municipal brigade name
  assigned_organization_id UUID REFERENCES public.organizations(id),
  contractor_name TEXT,
  status TEXT NOT NULL DEFAULT 'unconfirmed',        -- unconfirmed, confirmed, in_progress, repaired, verified, rejected
  priority_level TEXT NOT NULL DEFAULT 'MEDIUM',     -- CRITICAL, HIGH, MEDIUM, LOW
  due_date DATE,
  estimated_cost_tnd NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
  actual_cost_tnd NUMERIC(10, 2),
  repair_notes TEXT,
  verification_status TEXT NOT NULL DEFAULT 'pending', -- pending, passed, rejected
  verified_by TEXT,
  verified_at TIMESTAMPTZ,
  verification_notes TEXT,
  road_segment_id UUID REFERENCES public.road_segments(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_maintenance_cases_obs ON public.maintenance_cases (observation_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_cases_status ON public.maintenance_cases (status);
CREATE INDEX IF NOT EXISTS idx_maintenance_cases_priority ON public.maintenance_cases (priority_level);
CREATE INDEX IF NOT EXISTS idx_maintenance_cases_due_date ON public.maintenance_cases (due_date);

-- -----------------------------------------------------------------------------
-- 3. Maintenance Audit Events Table (Chronological Traceability)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.maintenance_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  observation_id TEXT NOT NULL REFERENCES public.observations(id) ON DELETE CASCADE,
  maintenance_case_id UUID REFERENCES public.maintenance_cases(id) ON DELETE SET NULL,
  user_id UUID,
  actor_email TEXT,
  action TEXT NOT NULL,                              -- 'status_change', 'assignment', 'priority_update', 'due_date_set', 'verified', 'rejected', 'note_added', 'export'
  previous_value TEXT,
  new_value TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_maintenance_events_obs ON public.maintenance_events (observation_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_events_action ON public.maintenance_events (action);
CREATE INDEX IF NOT EXISTS idx_maintenance_events_created ON public.maintenance_events (created_at DESC);

-- -----------------------------------------------------------------------------
-- 4. Initial Backfill: Ensure each observation has a maintenance case
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  INSERT INTO public.maintenance_cases (
    observation_id,
    case_number,
    status,
    priority_level,
    estimated_cost_tnd,
    created_at,
    updated_at
  )
  SELECT
    o.id,
    'CASE-' || TO_CHAR(o.created_at, 'YYYY') || '-' || LPAD(SUBSTRING(o.id FROM 1 FOR 6), 6, '0'),
    COALESCE(o.status, 'unconfirmed'),
    CASE
      WHEN UPPER(COALESCE(o.priority_label, '')) IN ('CRITICAL', 'HIGH') THEN 'HIGH'
      WHEN UPPER(COALESCE(o.priority_label, '')) = 'LOW' THEN 'LOW'
      WHEN COALESCE(o.priority_score, 0) >= 65 THEN 'HIGH'
      WHEN COALESCE(o.priority_score, 0) <= 35 THEN 'LOW'
      ELSE 'MEDIUM'
    END,
    CASE
      WHEN o.anomaly_type = 'D40' THEN 280.00
      WHEN o.anomaly_type = 'D20' THEN 450.00
      WHEN o.anomaly_type IN ('D00', 'D10') THEN 120.00
      ELSE 200.00
    END,
    o.created_at,
    o.created_at
  FROM public.observations o
  ON CONFLICT (observation_id) DO NOTHING;
END $$;

-- -----------------------------------------------------------------------------
-- 5. Row Level Security & Permissions
-- -----------------------------------------------------------------------------
ALTER TABLE public.road_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_events ENABLE ROW LEVEL SECURITY;

-- Permissions on road_segments
GRANT SELECT ON public.road_segments TO anon, authenticated;
DROP POLICY IF EXISTS "allow_read_road_segments" ON public.road_segments;
CREATE POLICY "allow_read_road_segments" ON public.road_segments
  FOR SELECT TO anon, authenticated USING (true);

-- Permissions on maintenance_cases
GRANT SELECT, INSERT, UPDATE ON public.maintenance_cases TO anon, authenticated;

DROP POLICY IF EXISTS "anon_select_maintenance_cases" ON public.maintenance_cases;
CREATE POLICY "anon_select_maintenance_cases" ON public.maintenance_cases
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "authority_manage_maintenance_cases" ON public.maintenance_cases;
CREATE POLICY "authority_manage_maintenance_cases" ON public.maintenance_cases
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.authority_users au
      WHERE au.user_id = auth.uid()
    ) OR public.is_authority()
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.authority_users au
      WHERE au.user_id = auth.uid()
    ) OR public.is_authority()
  );

-- Permissions on maintenance_events
GRANT SELECT, INSERT ON public.maintenance_events TO anon, authenticated;

DROP POLICY IF EXISTS "anon_select_maintenance_events" ON public.maintenance_events;
CREATE POLICY "anon_select_maintenance_events" ON public.maintenance_events
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authority_insert_maintenance_events" ON public.maintenance_events;
CREATE POLICY "authority_insert_maintenance_events" ON public.maintenance_events
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.authority_users au
      WHERE au.user_id = auth.uid()
    ) OR public.is_authority()
  );

-- -----------------------------------------------------------------------------
-- 6. Server-Side Function: get_road_segment_risk
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_road_segment_risk(
  min_risk_level text DEFAULT 'ALL'
)
RETURNS TABLE (
  segment_id uuid,
  segment_code text,
  segment_name text,
  road_type text,
  governorate text,
  municipality text,
  importance_weight numeric,
  report_count bigint,
  active_count bigint,
  repaired_count bigint,
  dominant_class text,
  max_priority_score double precision,
  oldest_report_days integer,
  risk_score numeric,
  risk_level text,
  estimated_budget_tnd numeric,
  explanation text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH matched_reports AS (
    SELECT
      s.id AS seg_id,
      s.code AS seg_code,
      s.name AS seg_name,
      s.road_type AS seg_type,
      s.governorate AS seg_gov,
      s.municipality AS seg_mun,
      s.importance_weight AS seg_weight,
      o.id AS obs_id,
      o.anomaly_type,
      COALESCE(o.priority_score, 50.0) AS priority_score,
      COALESCE(o.status, 'unconfirmed') AS status,
      o.created_at,
      l.accuracy_meters
    FROM public.road_segments s
    JOIN public.locations l ON (
      -- Match within 3.5 km of segment representative coordinate or bounding zone
      ST_DWithin(
        ST_SetSRID(ST_MakePoint(l.longitude, l.latitude), 4326)::geography,
        ST_SetSRID(ST_MakePoint(s.centroid_lng, s.centroid_lat), 4326)::geography,
        3500
      )
    )
    JOIN public.observations o ON o.id = l.observation_id
    WHERE o.status <> 'rejected'
  ),
  aggregated AS (
    SELECT
      m.seg_id,
      m.seg_code,
      m.seg_name,
      m.seg_type,
      m.seg_gov,
      m.seg_mun,
      m.seg_weight,
      COUNT(*)::bigint AS rep_count,
      COUNT(*) FILTER (WHERE m.status IN ('unconfirmed', 'confirmed', 'in_progress'))::bigint AS act_count,
      COUNT(*) FILTER (WHERE m.status = 'repaired')::bigint AS rep_done_count,
      CASE
        WHEN bool_or(m.anomaly_type = 'D40') THEN 'D40'
        WHEN bool_or(m.anomaly_type = 'D20') THEN 'D20'
        WHEN bool_or(m.anomaly_type = 'D10') THEN 'D10'
        WHEN bool_or(m.anomaly_type = 'D00') THEN 'D00'
        ELSE 'D40'
      END AS dom_class,
      ROUND(COALESCE(MAX(m.priority_score), 0)::numeric, 1)::double precision AS max_p_score,
      COALESCE(EXTRACT(DAY FROM (now() - MIN(m.created_at)))::integer, 0) AS old_days,
      SUM(
        CASE
          WHEN m.anomaly_type = 'D40' THEN 280.00
          WHEN m.anomaly_type = 'D20' THEN 450.00
          WHEN m.anomaly_type IN ('D00', 'D10') THEN 120.00
          ELSE 200.00
        END
      ) AS est_budget
    FROM matched_reports m
    GROUP BY m.seg_id, m.seg_code, m.seg_name, m.seg_type, m.seg_gov, m.seg_mun, m.seg_weight
  ),
  scored AS (
    SELECT
      a.*,
      ROUND(
        (
          -- Base score from dominant class severity
          CASE
            WHEN a.dom_class = 'D40' THEN 35.0
            WHEN a.dom_class = 'D20' THEN 28.0
            WHEN a.dom_class = 'D10' THEN 18.0
            ELSE 15.0
          END +
          -- Max priority score component (scaled)
          (a.max_p_score * 0.25) +
          -- Volume component
          LEAST(a.act_count * 4.0, 20.0) +
          -- Age of backlog component
          LEAST(a.old_days * 0.35, 15.0)
        ) * a.seg_weight,
        1
      ) AS calc_risk_score
    FROM aggregated a
  )
  SELECT
    s.seg_id,
    s.seg_code,
    s.seg_name,
    s.seg_type,
    s.seg_gov,
    s.seg_mun,
    s.seg_weight,
    s.rep_count,
    s.act_count,
    s.rep_done_count,
    s.dom_class,
    s.max_p_score,
    s.old_days,
    s.calc_risk_score,
    CASE
      WHEN s.calc_risk_score >= 70.0 THEN 'CRITICAL'
      WHEN s.calc_risk_score >= 50.0 THEN 'HIGH'
      WHEN s.calc_risk_score >= 30.0 THEN 'MEDIUM'
      ELSE 'LOW'
    END AS risk_lvl,
    ROUND(s.est_budget, 2) AS est_budget,
    'Score calculé : ' || s.act_count || ' dégradations actives, ' ||
      (CASE WHEN s.dom_class = 'D40' THEN 'présence de nids-de-poule D40' ELSE 'faïençage / fissures' END) ||
      ', ancienneté de ' || s.old_days || ' j, pondération axe ' || s.seg_weight AS expl
  FROM scored s
  WHERE
    min_risk_level = 'ALL' OR
    (min_risk_level = 'CRITICAL' AND s.calc_risk_score >= 70.0) OR
    (min_risk_level = 'HIGH' AND s.calc_risk_score >= 50.0) OR
    (min_risk_level = 'MEDIUM' AND s.calc_risk_score >= 30.0)
  ORDER BY s.calc_risk_score DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_road_segment_risk(text) TO anon, authenticated;

-- -----------------------------------------------------------------------------
-- 7. Server-Side Function: get_anomalies_in_bounds (Viewport live map queries)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_anomalies_in_bounds(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  status_filter text DEFAULT 'all',
  class_filter text DEFAULT 'all',
  priority_filter text DEFAULT 'all',
  include_demo boolean DEFAULT true,
  max_results integer DEFAULT 250
)
RETURNS TABLE (
  observation_id text,
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  anomaly_type text,
  priority_score double precision,
  priority_label text,
  status text,
  is_demo boolean,
  created_at timestamptz,
  organization_name text,
  assigned_to text,
  due_date date,
  estimated_cost_tnd numeric
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT
    o.id,
    l.latitude,
    l.longitude,
    l.accuracy_meters,
    o.anomaly_type,
    o.priority_score,
    o.priority_label,
    o.status,
    o.is_demo,
    o.created_at,
    COALESCE(org.name, 'Municipality'),
    mc.assigned_to,
    mc.due_date,
    mc.estimated_cost_tnd
  FROM public.observations o
  JOIN public.locations l ON l.observation_id = o.id
  LEFT JOIN public.organizations org ON org.id = o.organization_id
  LEFT JOIN public.maintenance_cases mc ON mc.observation_id = o.id
  WHERE
    l.latitude BETWEEN min_lat AND max_lat
    AND l.longitude BETWEEN min_lng AND max_lng
    AND (include_demo OR NOT o.is_demo)
    AND (status_filter = 'all' OR o.status = status_filter)
    AND (class_filter = 'all' OR o.anomaly_type = class_filter)
    AND (priority_filter = 'all' OR UPPER(COALESCE(o.priority_label, '')) = UPPER(priority_filter))
  ORDER BY o.priority_score DESC NULLS LAST, o.created_at DESC
  LIMIT LEAST(max_results, 500);
$$;

GRANT EXECUTE ON FUNCTION public.get_anomalies_in_bounds(double precision, double precision, double precision, double precision, text, text, text, boolean, integer) TO anon, authenticated;

COMMENT ON TABLE public.maintenance_cases IS 'Authoritative maintenance work cases, contractor assignments, deadlines, and repair verification states.';
COMMENT ON TABLE public.maintenance_events IS 'Chronological audit trail of all status transitions, contractor assignments, priority adjustments, and verification actions.';
COMMENT ON TABLE public.road_segments IS 'Canonical network corridors and segments used for spatial risk aggregation and priority triage.';
