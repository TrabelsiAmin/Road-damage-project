-- Phase 1c (rewritten): least-privilege grants, authority read access, retire live_sessions.
-- Phone app = anonymous, no accounts. Authority dashboard = the only authenticated user type.

-- 1. Remove blanket grants (anon had TRUNCATE/DELETE/UPDATE everywhere; TRUNCATE bypasses RLS).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['agent_runs','detection_classes','detections','devices','live_sessions','locations',
    'media','media_files','memberships','model_versions','organization_types','organizations','profiles','roles','sync_receipts']
  LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
  END LOOP;
  BEGIN
    EXECUTE 'REVOKE ALL ON public.spatial_ref_sys, public.geography_columns, public.geometry_columns FROM anon, authenticated';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'postgis system tables not revoked: %', SQLERRM;
  END;
END $$;

-- 2. Anonymous phone app: insert-only on the sync tables, read-only on public map data.
GRANT INSERT ON public.locations, public.detections, public.agent_runs, public.sync_receipts, public.media_files TO anon;
GRANT SELECT ON public.locations, public.detections, public.media_files TO anon;

-- 3. Authority dashboard (authenticated + is_authority()): read-only on what it needs.
GRANT SELECT ON public.locations, public.detections, public.agent_runs, public.sync_receipts,
                public.media_files, public.detection_classes TO authenticated;

-- 4. Policies: drop legacy account-based and duplicate policies.
DROP POLICY IF EXISTS "Enable insert for anonymous users" ON public.agent_runs;
DROP POLICY IF EXISTS "Enable insert for anonymous users" ON public.detections;
DROP POLICY IF EXISTS "Enable insert for anonymous users" ON public.locations;
DROP POLICY IF EXISTS "Enable insert for anonymous users" ON public.sync_receipts;
DROP POLICY IF EXISTS "Enable read for anonymous users" ON public.detections;
DROP POLICY IF EXISTS "Enable read for anonymous users" ON public.locations;
DROP POLICY IF EXISTS agent_runs_insert ON public.agent_runs;
DROP POLICY IF EXISTS agent_runs_update ON public.agent_runs;
DROP POLICY IF EXISTS agent_runs_select ON public.agent_runs;
DROP POLICY IF EXISTS detections_insert ON public.detections;
DROP POLICY IF EXISTS detections_update ON public.detections;
DROP POLICY IF EXISTS detections_select ON public.detections;
DROP POLICY IF EXISTS locations_insert ON public.locations;
DROP POLICY IF EXISTS locations_update ON public.locations;
DROP POLICY IF EXISTS locations_select ON public.locations;
DROP POLICY IF EXISTS sync_receipts_insert ON public.sync_receipts;
DROP POLICY IF EXISTS sync_receipts_update ON public.sync_receipts;
DROP POLICY IF EXISTS sync_receipts_select ON public.sync_receipts;
DROP POLICY IF EXISTS media_insert ON public.media;
DROP POLICY IF EXISTS media_update ON public.media;
DROP POLICY IF EXISTS media_select ON public.media;
DROP POLICY IF EXISTS devices_insert ON public.devices;
DROP POLICY IF EXISTS devices_update ON public.devices;
DROP POLICY IF EXISTS devices_select ON public.devices;

-- Anonymous reads (public map): coordinates and detections carry no device id.
CREATE POLICY anon_select_locations  ON public.locations  FOR SELECT TO anon USING (true);
CREATE POLICY anon_select_detections ON public.detections FOR SELECT TO anon USING (true);

-- Authority reads.
CREATE POLICY authority_select_locations     ON public.locations     FOR SELECT TO authenticated USING (public.is_authority());
CREATE POLICY authority_select_detections    ON public.detections    FOR SELECT TO authenticated USING (public.is_authority());
CREATE POLICY authority_select_agent_runs    ON public.agent_runs    FOR SELECT TO authenticated USING (public.is_authority());
CREATE POLICY authority_select_sync_receipts ON public.sync_receipts FOR SELECT TO authenticated USING (public.is_authority());
CREATE POLICY authority_select_detection_classes ON public.detection_classes FOR SELECT TO authenticated USING (true);

-- 5. Authenticated users must not insert media_files / observations (only the anonymous phone app does).
DROP POLICY IF EXISTS anon_insert_media_files ON public.media_files;
CREATE POLICY anon_insert_media_files ON public.media_files FOR INSERT TO anon WITH CHECK (is_demo = false);

-- 6. Retire live scan: no policies, no grants, bucket private, no anon storage access. Data kept.
DROP POLICY IF EXISTS anon_insert_live_sessions ON public.live_sessions;
DROP POLICY IF EXISTS anon_select_live_sessions ON public.live_sessions;
DROP POLICY IF EXISTS anon_update_live_sessions ON public.live_sessions;
DROP POLICY IF EXISTS anon_upload_session_videos ON storage.objects;
DROP POLICY IF EXISTS public_read_session_videos ON storage.objects;
UPDATE storage.buckets SET public = false WHERE id = 'live-session-videos';
COMMENT ON TABLE public.live_sessions IS 'DEPRECATED: live scan feature removed. No grants or policies. Safe to drop once data is no longer needed.';

-- 7. Unauthenticated users cannot upload to observation-images only as anon (authenticated upload not needed).
DROP POLICY IF EXISTS anon_upload_observation_images ON storage.objects;
CREATE POLICY anon_upload_observation_images ON storage.objects FOR INSERT TO anon
  WITH CHECK (bucket_id = 'observation-images');