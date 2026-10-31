-- =============================================================================
-- Migration: 20261016_atomic_ingest_and_validation.sql
-- 
-- Objectives:
--   1. Secure organization table permissions and seed canonical authorities.
--   2. Atomic observation ingestion RPC (submit_observation) with full
--      server-side validation (Priority 0: A & B).
--   3. Idempotent execution preventing partial rows and duplicate records.
--   4. Enforce security boundaries (status='unconfirmed', is_demo=false, valid bounds).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Organizations Table Hardening & Permissions
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  code TEXT UNIQUE,
  name_fr TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS name_fr TEXT;
ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS code TEXT;

-- Seed canonical organizations if missing
INSERT INTO public.organizations (id, name, code, name_fr, is_active)
VALUES
  ('11111111-1111-4111-8111-111111111111', 'Municipality', 'MUNICIPALITY', 'Commune', true),
  ('22222222-2222-4222-8222-222222222222', 'Ministry of Equipment', 'MINISTRY_OF_EQUIPMENT', 'Ministère de l''Équipement', true),
  ('33333333-3333-4333-8333-333333333333', 'Tunisia Autoroutes', 'TUNISIA_AUTOROUTES', 'Tunisie Autoroutes', true)
ON CONFLICT (id) DO UPDATE
SET is_active = true,
    code = COALESCE(public.organizations.code, EXCLUDED.code),
    name_fr = COALESCE(public.organizations.name_fr, EXCLUDED.name_fr);

-- Ensure anon & authenticated can safely read active organizations
GRANT SELECT ON public.organizations TO anon, authenticated;
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_organizations" ON public.organizations;
CREATE POLICY "anon_select_organizations"
  ON public.organizations
  FOR SELECT
  TO anon
  USING (is_active = true);

DROP POLICY IF EXISTS "auth_select_organizations" ON public.organizations;
CREATE POLICY "auth_select_organizations"
  ON public.organizations
  FOR SELECT
  TO authenticated
  USING (true);

-- -----------------------------------------------------------------------------
-- 2. Known Model Bundle Versions Whitelist Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.known_model_versions (
  version TEXT PRIMARY KEY,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.known_model_versions (version, description, is_active)
VALUES
  ('2026.09.23-rdd2022', 'Standard RDD2022 legacy model', true),
  ('2026.10.15-roadsense', 'RoadSense experimental hybrid model', true)
ON CONFLICT (version) DO NOTHING;

GRANT SELECT ON public.known_model_versions TO anon, authenticated;
ALTER TABLE public.known_model_versions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anyone_select_known_model_versions" ON public.known_model_versions;
CREATE POLICY "anyone_select_known_model_versions"
  ON public.known_model_versions
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- -----------------------------------------------------------------------------
-- 3. Atomic Ingestion RPC: submit_observation
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_observation(
  p_observation jsonb,
  p_location jsonb,
  p_agent_runs jsonb DEFAULT '[]'::jsonb,
  p_detections jsonb DEFAULT '[]'::jsonb,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_obs_id UUID;
  v_capture_id UUID;
  v_org_id UUID;
  v_lat DOUBLE PRECISION;
  v_lng DOUBLE PRECISION;
  v_accuracy DOUBLE PRECISION;
  v_priority_score NUMERIC;
  v_priority_label TEXT;
  v_anomaly_type TEXT;
  v_model_version TEXT;
  v_img_w INTEGER;
  v_img_h INTEGER;
  v_captured_at TIMESTAMPTZ;
  v_idem_key TEXT;
  
  v_run jsonb;
  v_det jsonb;
  v_run_id UUID;
  v_det_id UUID;
  v_det_class TEXT;
  v_det_conf DOUBLE PRECISION;
  v_box_x DOUBLE PRECISION;
  v_box_y DOUBLE PRECISION;
  v_box_w DOUBLE PRECISION;
  v_box_h DOUBLE PRECISION;
  v_has_detections BOOLEAN := false;
  v_anomaly_matched BOOLEAN := false;
BEGIN
  -- 1. Extract observation fields
  BEGIN
    v_obs_id := (p_observation->>'id')::UUID;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Invalid observation ID: %', p_observation->>'id';
  END;

  BEGIN
    v_capture_id := (p_observation->>'capture_id')::UUID;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Invalid capture ID: %', p_observation->>'capture_id';
  END;

  BEGIN
    v_org_id := (p_observation->>'organization_id')::UUID;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Invalid organization ID: %', p_observation->>'organization_id';
  END;

  v_idem_key := COALESCE(p_idempotency_key, p_observation->>'id');

  -- 2. Idempotency Check: if sync receipt or observation exists, return success idempotently
  IF EXISTS (SELECT 1 FROM public.sync_receipts WHERE observation_id = v_obs_id OR idempotency_key = v_idem_key) THEN
    RETURN jsonb_build_object(
      'success', true,
      'status', 'already_synced',
      'observation_id', v_obs_id
    );
  END IF;

  IF EXISTS (SELECT 1 FROM public.observations WHERE id = v_obs_id) THEN
    RETURN jsonb_build_object(
      'success', true,
      'status', 'already_synced',
      'observation_id', v_obs_id
    );
  END IF;

  -- 3. Server-side Validations
  -- 3.1 Organization validation
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = v_org_id AND is_active = true) THEN
    RAISE EXCEPTION 'Organization % does not exist or is inactive', v_org_id;
  END IF;

  -- 3.2 Location validation
  v_lat := (p_location->>'latitude')::DOUBLE PRECISION;
  v_lng := (p_location->>'longitude')::DOUBLE PRECISION;
  v_accuracy := (p_location->>'accuracy_meters')::DOUBLE PRECISION;

  IF v_lat IS NULL OR v_lat < -90.0 OR v_lat > 90.0 THEN
    RAISE EXCEPTION 'Invalid latitude: %. Must be between -90 and 90', v_lat;
  END IF;

  IF v_lng IS NULL OR v_lng < -180.0 OR v_lng > 180.0 THEN
    RAISE EXCEPTION 'Invalid longitude: %. Must be between -180 and 180', v_lng;
  END IF;

  IF v_accuracy IS NOT NULL AND v_accuracy < 0.0 THEN
    RAISE EXCEPTION 'Invalid accuracy: %. Must be non-negative', v_accuracy;
  END IF;

  -- 3.3 Priority validation
  v_priority_score := (p_observation->>'priority_score')::NUMERIC;
  IF v_priority_score IS NOT NULL AND (v_priority_score < 0.0 OR v_priority_score > 100.0) THEN
    RAISE EXCEPTION 'Invalid priority score: %. Must be between 0 and 100', v_priority_score;
  END IF;

  v_priority_label := p_observation->>'priority_label';
  IF v_priority_label IS NOT NULL AND v_priority_label NOT IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL') THEN
    RAISE EXCEPTION 'Invalid priority label: %. Must be LOW, MEDIUM, HIGH, or CRITICAL', v_priority_label;
  END IF;

  -- 3.4 Anomaly type validation
  v_anomaly_type := p_observation->>'anomaly_type';
  IF v_anomaly_type IS NOT NULL AND v_anomaly_type NOT IN ('D00', 'D10', 'D20', 'D40') THEN
    RAISE EXCEPTION 'Invalid anomaly type: %. Must be D00, D10, D20, or D40', v_anomaly_type;
  END IF;

  -- 3.5 Image dimensions validation
  v_img_w := (p_observation->>'image_width')::INTEGER;
  v_img_h := (p_observation->>'image_height')::INTEGER;
  IF v_img_w IS NOT NULL AND v_img_w <= 0 THEN
    RAISE EXCEPTION 'Invalid image width: %. Must be positive', v_img_w;
  END IF;
  IF v_img_h IS NOT NULL AND v_img_h <= 0 THEN
    RAISE EXCEPTION 'Invalid image height: %. Must be positive', v_img_h;
  END IF;

  -- 3.6 Model bundle version validation
  v_model_version := p_observation->>'model_bundle_version';
  IF v_model_version IS NULL OR v_model_version = '' THEN
    v_model_version := '2026.09.23-rdd2022';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.known_model_versions WHERE version = v_model_version) THEN
    v_model_version := 'unknown_for_review:' || substr(v_model_version, 1, 30);
  END IF;

  -- 3.7 Validate detections & consistency
  IF p_detections IS NOT NULL AND jsonb_array_length(p_detections) > 0 THEN
    v_has_detections := true;
    FOR v_det IN SELECT * FROM jsonb_array_elements(p_detections)
    LOOP
      v_det_class := v_det->>'class_code';
      IF v_det_class NOT IN ('D00', 'D10', 'D20', 'D40') THEN
        RAISE EXCEPTION 'Invalid detection class: %. Must be D00, D10, D20, or D40', v_det_class;
      END IF;

      IF v_anomaly_type IS NOT NULL AND v_det_class = v_anomaly_type THEN
        v_anomaly_matched := true;
      END IF;

      v_det_conf := (v_det->>'confidence')::DOUBLE PRECISION;
      IF v_det_conf < 0.0 OR v_det_conf > 1.0 THEN
        RAISE EXCEPTION 'Invalid detection confidence: %. Must be between 0 and 1', v_det_conf;
      END IF;

      v_box_x := (v_det->>'box_x')::DOUBLE PRECISION;
      v_box_y := (v_det->>'box_y')::DOUBLE PRECISION;
      v_box_w := (v_det->>'box_w')::DOUBLE PRECISION;
      v_box_h := (v_det->>'box_h')::DOUBLE PRECISION;

      IF v_box_x < 0.0 OR v_box_x > 1.0 OR
         v_box_y < 0.0 OR v_box_y > 1.0 OR
         v_box_w < 0.0 OR v_box_w > 1.0 OR
         v_box_h < 0.0 OR v_box_h > 1.0 THEN
        RAISE EXCEPTION 'Bounding box coordinates must be normalized between 0 and 1';
      END IF;
    END LOOP;

    -- Submitted anomaly_type must match at least one of the detection classes
    IF v_anomaly_type IS NOT NULL AND NOT v_anomaly_matched THEN
      RAISE EXCEPTION 'Submitted anomaly type % does not match any detection class', v_anomaly_type;
    END IF;
  END IF;

  v_captured_at := COALESCE(
    (p_observation->>'captured_at')::TIMESTAMPTZ,
    (p_location->>'captured_at')::TIMESTAMPTZ,
    now()
  );

  -- 4. Atomic Relational Inserts
  -- 4.1 Observations (Forced status='unconfirmed', is_demo=false)
  INSERT INTO public.observations (
    id,
    capture_id,
    organization_id,
    source,
    captured_at,
    image_width,
    image_height,
    priority_score,
    priority_label,
    anomaly_type,
    model_bundle_version,
    created_at,
    is_demo,
    status
  ) VALUES (
    v_obs_id,
    v_capture_id,
    v_org_id,
    COALESCE(p_observation->>'source', 'camera'),
    v_captured_at,
    v_img_w,
    v_img_h,
    v_priority_score,
    v_priority_label,
    v_anomaly_type,
    v_model_version,
    v_captured_at,
    false,
    'unconfirmed'
  );

  -- 4.2 Location
  INSERT INTO public.locations (
    observation_id,
    latitude,
    longitude,
    accuracy_meters,
    captured_at
  ) VALUES (
    v_obs_id,
    v_lat,
    v_lng,
    v_accuracy,
    v_captured_at
  );

  -- 4.3 Agent runs
  IF p_agent_runs IS NOT NULL AND jsonb_array_length(p_agent_runs) > 0 THEN
    FOR v_run IN SELECT * FROM jsonb_array_elements(p_agent_runs)
    LOOP
      v_run_id := COALESCE((v_run->>'id')::UUID, gen_random_uuid());
      INSERT INTO public.agent_runs (
        id,
        observation_id,
        agent,
        error,
        is_mock,
        latency_ms,
        model_bundle_version
      ) VALUES (
        v_run_id,
        v_obs_id,
        v_run->>'agent',
        v_run->>'error',
        COALESCE((v_run->>'is_mock')::BOOLEAN, false),
        (v_run->>'latency_ms')::INTEGER,
        COALESCE(v_run->>'model_bundle_version', v_model_version)
      );
    END LOOP;
  END IF;

  -- 4.4 Detections
  IF v_has_detections THEN
    FOR v_det IN SELECT * FROM jsonb_array_elements(p_detections)
    LOOP
      v_det_id := COALESCE((v_det->>'id')::UUID, gen_random_uuid());
      INSERT INTO public.detections (
        id,
        observation_id,
        agent_run_id,
        class_code,
        confidence,
        box_x,
        box_y,
        box_w,
        box_h,
        frame_index,
        is_mock,
        model_bundle_version,
        detected_at
      ) VALUES (
        v_det_id,
        v_obs_id,
        (v_det->>'agent_run_id')::UUID,
        v_det->>'class_code',
        (v_det->>'confidence')::DOUBLE PRECISION,
        (v_det->>'box_x')::DOUBLE PRECISION,
        (v_det->>'box_y')::DOUBLE PRECISION,
        (v_det->>'box_w')::DOUBLE PRECISION,
        (v_det->>'box_h')::DOUBLE PRECISION,
        (v_det->>'frame_index')::INTEGER,
        COALESCE((v_det->>'is_mock')::BOOLEAN, false),
        COALESCE(v_det->>'model_bundle_version', v_model_version),
        COALESCE((v_det->>'detected_at')::TIMESTAMPTZ, v_captured_at)
      );
    END LOOP;
  END IF;

  -- 4.5 Sync receipt
  INSERT INTO public.sync_receipts (
    observation_id,
    idempotency_key,
    payload_hash,
    received_at
  ) VALUES (
    v_obs_id,
    v_idem_key,
    'atomic-rpc-sync',
    now()
  );

  RETURN jsonb_build_object(
    'success', true,
    'status', 'synced',
    'observation_id', v_obs_id
  );
END;
$$;

-- Grant execution to anon and authenticated
GRANT EXECUTE ON FUNCTION public.submit_observation(jsonb, jsonb, jsonb, jsonb, text) TO anon, authenticated;
