-- ============================================================
-- Migration: 20261013_security_and_phase1.sql
-- Description:
--   1. Adds `is_demo` and workflow `status` columns to observations.
--   2. Hardens Row Level Security (RLS) policies against anonymous tampering.
--   3. Grants authenticated institutional operators permission to triage,
--      schedule, and update observation statuses.
-- ============================================================

-- 1. Schema Additions
ALTER TABLE public.observations
  ADD COLUMN IF NOT EXISTS is_demo BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.observations
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'unconfirmed'
  CHECK (status IN ('unconfirmed', 'confirmed', 'scheduled', 'repaired', 'verified', 'dismissed'));

CREATE INDEX IF NOT EXISTS idx_observations_is_demo
  ON public.observations (is_demo);

CREATE INDEX IF NOT EXISTS idx_observations_status
  ON public.observations (status);

-- 2. Revoke Unsafe Anonymous Modification Policies
-- Prevent anonymous attackers from overwriting priority scores, coordinates, or labels.
DROP POLICY IF EXISTS "anon_update_observations" ON public.observations;

-- 3. Authenticated Authority Operator Policies
-- Authorized dashboard operators (Supabase Auth email/password) have full triage rights.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'observations' AND policyname = 'authenticated_update_observations'
  ) THEN
    CREATE POLICY "authenticated_update_observations"
      ON public.observations FOR UPDATE TO authenticated
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'observations' AND policyname = 'authenticated_select_observations'
  ) THEN
    CREATE POLICY "authenticated_select_observations"
      ON public.observations FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

-- 4. Public / Anonymous Read Policy
-- Allow anonymous users (and public dashboard views) to read observations and locations.
-- For privacy compliance, real field imagery in media_files is restricted to authenticated users.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'observations' AND policyname = 'public_read_observations'
  ) THEN
    CREATE POLICY "public_read_observations"
      ON public.observations FOR SELECT TO anon
      USING (true);
  END IF;
END $$;

-- 5. Media Files Privacy
-- Demo media is public; real field photos are viewable by authenticated authority users.
DROP POLICY IF EXISTS "anon_select_media_files" ON public.media_files;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'media_files' AND policyname = 'authenticated_read_media_files'
  ) THEN
    CREATE POLICY "authenticated_read_media_files"
      ON public.media_files FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'media_files' AND policyname = 'public_read_demo_media_files'
  ) THEN
    CREATE POLICY "public_read_demo_media_files"
      ON public.media_files FOR SELECT TO anon
      USING (
        EXISTS (
          SELECT 1 FROM public.observations o
          WHERE o.id = media_files.observation_id AND o.is_demo = true
        )
      );
  END IF;
END $$;
