-- ============================================================
-- Fix RLS Policies for Mobile App Direct Inserts
-- The app now uses the anon key to write directly to Supabase
-- instead of going through the Python FastAPI backend.
-- We must allow anon INSERT for these existing tables.
-- ============================================================

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='anon_insert_observations') THEN
    CREATE POLICY "anon_insert_observations" ON public.observations FOR INSERT TO anon WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='anon_update_observations') THEN
    CREATE POLICY "anon_update_observations" ON public.observations FOR UPDATE TO anon USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='anon_insert_locations') THEN
    CREATE POLICY "anon_insert_locations" ON public.locations FOR INSERT TO anon WITH CHECK (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='anon_insert_agent_runs') THEN
    CREATE POLICY "anon_insert_agent_runs" ON public.agent_runs FOR INSERT TO anon WITH CHECK (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='anon_insert_detections') THEN
    CREATE POLICY "anon_insert_detections" ON public.detections FOR INSERT TO anon WITH CHECK (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='anon_insert_sync_receipts') THEN
    CREATE POLICY "anon_insert_sync_receipts" ON public.sync_receipts FOR INSERT TO anon WITH CHECK (true);
  END IF;
END $$;
