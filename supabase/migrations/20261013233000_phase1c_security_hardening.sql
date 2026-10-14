-- =============================================================================
-- Migration: 20261013233000_phase1c_security_hardening.sql (Phase 1c)
--
-- Security Hardening for LIVE Supabase Project:
--   1. Spatial ref sys: Revoke INSERT, UPDATE, DELETE, TRUNCATE on spatial_ref_sys
--      from anon and authenticated while keeping SELECT for PostGIS.
--   2. Storage: Bucket live-session-videos made private, file_size_limit lowered
--      from 500 MB to 100 MB, drop public_read_session_videos policy, and add
--      authority-only read policy (public.is_authority()).
--   3. live_sessions column privileges: Revoke SELECT from anon, grant explicit
--      column list excluding device_id to prevent anon device tracking.
--   4. Privilege minimization: Remove excess privileges (DELETE, UPDATE, TRUNCATE,
--      TRIGGER, REFERENCES) from anon/authenticated across public tables, matching
--      exact policy requirements.
--   5. Function privileges: Revoke EXECUTE from PUBLIC and anon on internal functions
--      (can_read_observation, handle_new_user, is_org_member, observation_object_allowed).
--      Keep is_authority() executable by authenticated.
--   6. Default privileges: Revoke automatic default grants on future tables/functions.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. spatial_ref_sys Hardening (PostGIS)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.spatial_ref_sys FROM anon, authenticated;
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping REVOKE on public.spatial_ref_sys: current role does not own spatial_ref_sys (owned by supabase_admin)';
  WHEN OTHERS THEN
    RAISE NOTICE 'REVOKE on public.spatial_ref_sys notice: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- 2. Bucket live-session-videos Privacy & Access Control
-- -----------------------------------------------------------------------------
UPDATE storage.buckets
SET public = false,
    file_size_limit = 104857600 -- 100 MB (104,857,600 bytes, down from 500 MB)
WHERE id = 'live-session-videos';

DROP POLICY IF EXISTS "public_read_session_videos" ON storage.objects;
DROP POLICY IF EXISTS "authority_read_session_videos" ON storage.objects;

CREATE POLICY "authority_read_session_videos"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'live-session-videos' AND public.is_authority());

-- -----------------------------------------------------------------------------
-- 3. live_sessions Column-Level Grants (Hide device_id from anon)
-- -----------------------------------------------------------------------------
REVOKE SELECT ON public.live_sessions FROM anon;

GRANT SELECT (
  id, session_name, actor, started_at, ended_at, status,
  latitude, longitude, frame_count, anomaly_count, video_url,
  duration_s, notes, created_at, updated_at
) ON public.live_sessions TO anon;

GRANT SELECT ON public.live_sessions TO authenticated;

-- -----------------------------------------------------------------------------
-- 4. Minimize Privileges on Public Tables
-- -----------------------------------------------------------------------------

-- locations: anon INSERT + SELECT, authenticated INSERT + SELECT
REVOKE ALL ON public.locations FROM anon, authenticated;
GRANT INSERT, SELECT ON public.locations TO anon;
GRANT INSERT, SELECT ON public.locations TO authenticated;

-- detections: anon INSERT + SELECT, authenticated INSERT + SELECT
REVOKE ALL ON public.detections FROM anon, authenticated;
GRANT INSERT, SELECT ON public.detections TO anon;
GRANT INSERT, SELECT ON public.detections TO authenticated;

-- agent_runs: anon INSERT only, authenticated INSERT + SELECT
REVOKE ALL ON public.agent_runs FROM anon, authenticated;
GRANT INSERT ON public.agent_runs TO anon;
GRANT INSERT, SELECT ON public.agent_runs TO authenticated;

-- sync_receipts: anon INSERT only, authenticated INSERT + SELECT
REVOKE ALL ON public.sync_receipts FROM anon, authenticated;
GRANT INSERT ON public.sync_receipts TO anon;
GRANT INSERT, SELECT ON public.sync_receipts TO authenticated;

-- media_files: anon INSERT + SELECT, authenticated INSERT + SELECT
REVOKE ALL ON public.media_files FROM anon, authenticated;
GRANT INSERT, SELECT ON public.media_files TO anon;
GRANT INSERT, SELECT ON public.media_files TO authenticated;

-- live_sessions: anon INSERT + UPDATE + SELECT(columns), authenticated INSERT + UPDATE + SELECT
REVOKE ALL ON public.live_sessions FROM anon, authenticated;
GRANT INSERT, UPDATE ON public.live_sessions TO anon;
GRANT SELECT (
  id, session_name, actor, started_at, ended_at, status,
  latitude, longitude, frame_count, anomaly_count, video_url,
  duration_s, notes, created_at, updated_at
) ON public.live_sessions TO anon;
GRANT SELECT, INSERT, UPDATE ON public.live_sessions TO authenticated;

-- Legacy multi-tenant tables: revoke ALL from anon; keep only authenticated SELECT/UPDATE per policies
REVOKE ALL ON public.devices FROM anon, authenticated;
REVOKE ALL ON public.profiles FROM anon, authenticated;
REVOKE ALL ON public.memberships FROM anon, authenticated;
REVOKE ALL ON public.organizations FROM anon, authenticated;
REVOKE ALL ON public.organization_types FROM anon, authenticated;
REVOKE ALL ON public.roles FROM anon, authenticated;
REVOKE ALL ON public.media FROM anon, authenticated;
REVOKE ALL ON public.model_versions FROM anon, authenticated;
REVOKE ALL ON public.detection_classes FROM anon, authenticated;

-- Keep authenticated access for legacy reference queries
GRANT SELECT ON public.organizations TO authenticated;
GRANT SELECT ON public.organization_types TO authenticated;
GRANT SELECT ON public.roles TO authenticated;
GRANT SELECT ON public.model_versions TO authenticated;
GRANT SELECT ON public.detection_classes TO authenticated;
GRANT SELECT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT ON public.memberships TO authenticated;

-- -----------------------------------------------------------------------------
-- 5. Revoke EXECUTE on Internal Functions from PUBLIC and anon
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  -- can_read_observation
  BEGIN
    REVOKE EXECUTE ON FUNCTION public.can_read_observation FROM PUBLIC, anon;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'can_read_observation revoke notice: %', SQLERRM;
  END;

  -- handle_new_user
  BEGIN
    REVOKE EXECUTE ON FUNCTION public.handle_new_user FROM PUBLIC, anon;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'handle_new_user revoke notice: %', SQLERRM;
  END;

  -- is_org_member
  BEGIN
    REVOKE EXECUTE ON FUNCTION public.is_org_member FROM PUBLIC, anon;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'is_org_member revoke notice: %', SQLERRM;
  END;

  -- observation_object_allowed
  BEGIN
    REVOKE EXECUTE ON FUNCTION public.observation_object_allowed FROM PUBLIC, anon;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'observation_object_allowed revoke notice: %', SQLERRM;
  END;
END $$;

-- Keep is_authority executable by authenticated (RLS policies call it)
GRANT EXECUTE ON FUNCTION public.is_authority() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.is_authority() FROM anon, PUBLIC;

-- -----------------------------------------------------------------------------
-- 6. ALTER DEFAULT PRIVILEGES (Prevent Auto-Grant on Future Tables)
-- -----------------------------------------------------------------------------
-- Prevents PostgreSQL from automatically granting full privileges to anon/authenticated
-- when new tables or functions are created in public schema.
-- Trade-off: any new table created in future migrations MUST have explicit GRANT statements.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon, PUBLIC;
