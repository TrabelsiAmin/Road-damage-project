-- =============================================================================
-- Migration: 20261013_security_and_phase1.sql (Hardened Phase 1b)
--
-- Security Summary:
--   1. Role-based Authority table (public.authority_users) + is_authority() function.
--      "authenticated" != "authority". Only accounts in authority_users have triage rights.
--   2. observation-images bucket is PRIVATE; public reads dropped. Real photos require is_authority().
--      New public demo-images bucket for seed demonstration imagery.
--   3. live_sessions policy matches verified schema: status IN ('recording', 'completed', 'aborted').
--      Allows updates while status = 'recording' and transitions to completed/aborted.
--   4. Anon INSERT requires is_demo = false AND status = 'unconfirmed'. Demo rows require service_role.
--   5. device_id is hidden from anon via column privileges (anon cannot SELECT device_id).
--   6. Authenticated DELETE on observations is completely removed (demo cleanup via service_role only).
--   7. Drops all policies by exact audited names.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Schema Extensions & Authority Role Architecture
-- -----------------------------------------------------------------------------
ALTER TABLE public.observations 
  ADD COLUMN IF NOT EXISTS is_demo BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'unconfirmed'
    CHECK (status IN ('unconfirmed', 'confirmed', 'in_progress', 'repaired', 'rejected')),
  ADD COLUMN IF NOT EXISTS assigned_contractor TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS budget_estimate_tnd NUMERIC DEFAULT 0;

ALTER TABLE public.media_files
  ADD COLUMN IF NOT EXISTS is_demo BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_observations_demo ON public.observations (is_demo);
CREATE INDEX IF NOT EXISTS idx_observations_status ON public.observations (status);

-- Authority Users Table: explicit whitelist of authority accounts
CREATE TABLE IF NOT EXISTS public.authority_users (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.authority_users ENABLE ROW LEVEL SECURITY;

-- Helper function: is_authority()
-- SECURITY DEFINER, STABLE, fixed search_path to prevent hijacking
CREATE OR REPLACE FUNCTION public.is_authority()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.authority_users
    WHERE user_id = auth.uid()
  );
$$;

-- Allow authenticated users to check their own authority status
DROP POLICY IF EXISTS "auth_read_authority_users" ON public.authority_users;
CREATE POLICY "auth_read_authority_users"
  ON public.authority_users
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- 2. Drop Insecure Policies by Exact Audited Names
-- -----------------------------------------------------------------------------
-- Observations:
DROP POLICY IF EXISTS "anon_update_observations" ON public.observations;
DROP POLICY IF EXISTS "anon_delete_observations" ON public.observations;
DROP POLICY IF EXISTS "authenticated_update_observations" ON public.observations;
DROP POLICY IF EXISTS "authenticated_delete_observations" ON public.observations;
DROP POLICY IF EXISTS "auth_update_observations" ON public.observations;
DROP POLICY IF EXISTS "auth_delete_observations" ON public.observations;
DROP POLICY IF EXISTS "anon_insert_observations" ON public.observations;

-- Media files:
DROP POLICY IF EXISTS "anon_select_media_files" ON public.media_files;
DROP POLICY IF EXISTS "anon_insert_media_files" ON public.media_files;
DROP POLICY IF EXISTS "authenticated_read_media_files" ON public.media_files;
DROP POLICY IF EXISTS "public_read_demo_media_files" ON public.media_files;
DROP POLICY IF EXISTS "public_read_demo_media" ON public.media_files;
DROP POLICY IF EXISTS "auth_read_all_media" ON public.media_files;

-- Live sessions:
DROP POLICY IF EXISTS "anon_update_live_sessions" ON public.live_sessions;
DROP POLICY IF EXISTS "anon_update_live_sessions_progress" ON public.live_sessions;

-- Storage objects:
DROP POLICY IF EXISTS "public_read_observation_images" ON storage.objects;
DROP POLICY IF EXISTS "anon_read_observation_images" ON storage.objects;
DROP POLICY IF EXISTS "authority_read_observation_images" ON storage.objects;
DROP POLICY IF EXISTS "public_read_demo_images" ON storage.objects;
DROP POLICY IF EXISTS "anon_upload_observation_images" ON storage.objects;

-- -----------------------------------------------------------------------------
-- 3. Observations Hardened Policies
-- -----------------------------------------------------------------------------
-- Anonymous Ingest: must be real data (is_demo = false) and initial state (unconfirmed)
CREATE POLICY "anon_insert_observations"
  ON public.observations
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (is_demo = false AND status = 'unconfirmed');

-- Public Read: allows reading hazard data (map & public analytics)
-- device_id column privilege revoked below in Section 7
DROP POLICY IF EXISTS "public_read_observations" ON public.observations;
CREATE POLICY "public_read_observations"
  ON public.observations
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Authority Update: ONLY authority accounts can change status, contractor, or budget
CREATE POLICY "authority_update_observations"
  ON public.observations
  FOR UPDATE
  TO authenticated
  USING (public.is_authority())
  WITH CHECK (public.is_authority());

-- NOTE: No DELETE policy is created for observations.
-- Authenticated and anonymous DELETE are completely disallowed.
-- Demo data cleanup must be performed with the service_role key.

-- -----------------------------------------------------------------------------
-- 4. Media Files Privacy Policies
-- -----------------------------------------------------------------------------
-- Anonymous Upload: must be real data (is_demo = false)
CREATE POLICY "anon_insert_media_files"
  ON public.media_files
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (is_demo = false);

-- Public / Anonymous Read: demo media only
CREATE POLICY "anon_select_demo_media_files"
  ON public.media_files
  FOR SELECT
  TO anon
  USING (
    is_demo = true OR
    EXISTS (
      SELECT 1 FROM public.observations o
      WHERE o.id = media_files.observation_id AND o.is_demo = true
    )
  );

-- Authenticated Read: authority users can read real field media; regular users read demo only
CREATE POLICY "authority_select_media_files"
  ON public.media_files
  FOR SELECT
  TO authenticated
  USING (
    is_demo = true OR
    public.is_authority() OR
    EXISTS (
      SELECT 1 FROM public.observations o
      WHERE o.id = media_files.observation_id AND o.is_demo = true
    )
  );

-- -----------------------------------------------------------------------------
-- 5. Live Sessions Policy (Verified against status CHECK constraint)
-- Constraint: status IN ('recording', 'completed', 'aborted')
-- -----------------------------------------------------------------------------
CREATE POLICY "anon_update_live_sessions"
  ON public.live_sessions
  FOR UPDATE
  TO anon, authenticated
  USING (status = 'recording')
  WITH CHECK (status IN ('recording', 'completed', 'aborted'));

-- -----------------------------------------------------------------------------
-- 6. Storage Buckets Configuration & Access Control
-- -----------------------------------------------------------------------------
-- Ensure observation-images is PRIVATE with size limits and allowed MIME types
UPDATE storage.buckets
SET public = false,
    file_size_limit = 10485760, -- 10 MB
    allowed_mime_types = ARRAY['image/jpeg', 'image/webp', 'image/png']
WHERE id = 'observation-images';

-- Ensure demo-images bucket exists and is PUBLIC
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'demo-images',
  'demo-images',
  true,
  5242880, -- 5 MB
  ARRAY['image/jpeg', 'image/webp', 'image/png']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/webp', 'image/png'];

-- Storage: anon upload allowed for observation-images
CREATE POLICY "anon_upload_observation_images"
  ON storage.objects FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id = 'observation-images');

-- Storage: authority users can read/download from private observation-images
CREATE POLICY "authority_read_observation_images"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'observation-images' AND public.is_authority());

-- Storage: public read allowed for demo-images bucket
CREATE POLICY "public_read_demo_images"
  ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id = 'demo-images');

-- -----------------------------------------------------------------------------
-- 7. Hide device_id from Anonymous Callers (Column Privileges)
-- -----------------------------------------------------------------------------
REVOKE SELECT ON public.observations FROM anon;

GRANT SELECT (
  id, capture_id, parent_observation_id, created_by, organization_id,
  source, captured_at, image_width, image_height, priority_score,
  priority_label, anomaly_type, model_bundle_version, created_at,
  synced_at, is_demo, status, assigned_contractor, budget_estimate_tnd
) ON public.observations TO anon;

GRANT INSERT ON public.observations TO anon;
GRANT SELECT ON public.observations TO authenticated;
