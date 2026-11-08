-- Local development seed for the reviewed demo photographs.
-- NOT EXECUTED. Do not run this file against Supabase, staging, or production.
--
-- Isolation rule: the database name must be exactly tariqmap_dev_local.
-- A name that merely contains "dev" is not accepted. The server address must
-- be a local socket (NULL) or loopback. The only Supabase project visible to
-- this workspace is production lendqcjihusqkmxansbl. This file was not run there.
--
-- The guards and the inserts are one transaction and one DO block. There is
-- no INSERT statement outside that block. Copying the INSERT out still cannot
-- write rows: its own WHERE guard aborts the statement unless the same
-- database, server, cluster, and nullable-column checks pass.
--
-- Idempotent: inserts missing rows and does not update or delete anything.
-- It does not invent a priority score, a repair price, a bounding box, a GPS
-- fix, or a model version. Class codes below are the visual-review labels in
-- MANIFEST.json, not detector output.
--
-- supabase/seed/demo_data.sql is a different file. It deletes every is_demo
-- row. Do not run that file as a substitute for this one.
--
-- Residual limit: inet_server_addr() cannot see a tunnel or pooler that
-- terminates on the database machine, so a remote server can look local.
-- Do not point any client at a Supabase hostname, a pooler, or staging.
-- If this file is ever run, run it as one script against a local socket only:
--   psql -d tariqmap_dev_local -v ON_ERROR_STOP=1 \
--     -f evaluation/demo_dataset/seed_local_dev.sql
-- Confirm first that current_database() is tariqmap_dev_local and
-- inet_server_addr() is NULL or loopback. Do not pass -h for a remote host.

BEGIN;

DO $seed$
DECLARE
  server_addr inet := inet_server_addr();
  priority_nullable text;
  model_nullable text;
  org_nullable text;
BEGIN
  IF current_database() IS DISTINCT FROM 'tariqmap_dev_local' THEN
    RAISE EXCEPTION 'refusing seed: current_database() is %, expected tariqmap_dev_local', current_database();
  END IF;

  IF server_addr IS NOT NULL AND host(server_addr) NOT IN ('127.0.0.1', '::1') THEN
    RAISE EXCEPTION 'refusing seed: server address % is not loopback', server_addr;
  END IF;

  IF COALESCE(current_setting('cluster_name', true), '') ILIKE '%supabase%' THEN
    RAISE EXCEPTION 'refusing seed: cluster_name looks like Supabase';
  END IF;

  SELECT is_nullable INTO priority_nullable
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'observations' AND column_name = 'priority_score';

  SELECT is_nullable INTO model_nullable
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'observations' AND column_name = 'model_bundle_version';

  SELECT is_nullable INTO org_nullable
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'observations' AND column_name = 'organization_id';

  IF priority_nullable IS DISTINCT FROM 'YES'
     OR model_nullable IS DISTINCT FROM 'YES'
     OR org_nullable IS DISTINCT FROM 'YES' THEN
    RAISE EXCEPTION
      'refusing seed: observations.priority_score, model_bundle_version, and organization_id must all accept NULL. This seed does not invent a score, a model version, or an organization.';
  END IF;

  INSERT INTO public.observations (
    id, capture_id, organization_id, source, captured_at,
    image_width, image_height, priority_score, priority_label,
    anomaly_type, model_bundle_version, created_at, is_demo, status
  )
  SELECT
    seed.id, seed.capture_id, seed.organization_id, seed.source, seed.captured_at,
    seed.image_width, seed.image_height, seed.priority_score, seed.priority_label,
    seed.anomaly_type, seed.model_bundle_version, seed.created_at, seed.is_demo, seed.status
  FROM (VALUES
    ('a1100001-1111-4111-8111-000000000001'::uuid, 'b1100001-1111-4111-8111-000000000001'::uuid, NULL::uuid, 'demo_dataset', TIMESTAMPTZ '2026-11-08 00:00:00+00', 1280, 960, NULL::numeric, NULL::text, 'D40', NULL::text, TIMESTAMPTZ '2026-11-08 00:00:00+00', true, 'unconfirmed'),
    ('a1100001-1111-4111-8111-000000000002'::uuid, 'b1100001-1111-4111-8111-000000000002'::uuid, NULL::uuid, 'demo_dataset', TIMESTAMPTZ '2026-11-08 00:00:00+00', 1200, 1600, NULL::numeric, NULL::text, 'D40', NULL::text, TIMESTAMPTZ '2026-11-08 00:00:00+00', true, 'unconfirmed'),
    ('a1100001-1111-4111-8111-000000000003'::uuid, 'b1100001-1111-4111-8111-000000000003'::uuid, NULL::uuid, 'demo_dataset', TIMESTAMPTZ '2026-11-08 00:00:00+00', 1280, 853, NULL::numeric, NULL::text, 'D40', NULL::text, TIMESTAMPTZ '2026-11-08 00:00:00+00', true, 'unconfirmed'),
    ('a1100001-1111-4111-8111-000000000004'::uuid, 'b1100001-1111-4111-8111-000000000004'::uuid, NULL::uuid, 'demo_dataset', TIMESTAMPTZ '2026-11-08 00:00:00+00', 1280, 720, NULL::numeric, NULL::text, 'D20', NULL::text, TIMESTAMPTZ '2026-11-08 00:00:00+00', true, 'unconfirmed'),
    ('a1100001-1111-4111-8111-000000000005'::uuid, 'b1100001-1111-4111-8111-000000000005'::uuid, NULL::uuid, 'demo_dataset', TIMESTAMPTZ '2026-11-08 00:00:00+00', 1280, 1249, NULL::numeric, NULL::text, 'D20', NULL::text, TIMESTAMPTZ '2026-11-08 00:00:00+00', true, 'unconfirmed'),
    ('a1100001-1111-4111-8111-000000000006'::uuid, 'b1100001-1111-4111-8111-000000000006'::uuid, NULL::uuid, 'demo_dataset', TIMESTAMPTZ '2026-11-08 00:00:00+00', 1280, 1481, NULL::numeric, NULL::text, 'D20', NULL::text, TIMESTAMPTZ '2026-11-08 00:00:00+00', true, 'unconfirmed'),
    ('a1100001-1111-4111-8111-000000000007'::uuid, 'b1100001-1111-4111-8111-000000000007'::uuid, NULL::uuid, 'demo_dataset', TIMESTAMPTZ '2026-11-08 00:00:00+00', 1280, 1487, NULL::numeric, NULL::text, 'D00', NULL::text, TIMESTAMPTZ '2026-11-08 00:00:00+00', true, 'unconfirmed'),
    ('a1100001-1111-4111-8111-000000000008'::uuid, 'b1100001-1111-4111-8111-000000000008'::uuid, NULL::uuid, 'demo_dataset', TIMESTAMPTZ '2026-11-08 00:00:00+00', 1280, 960, NULL::numeric, NULL::text, 'D00', NULL::text, TIMESTAMPTZ '2026-11-08 00:00:00+00', true, 'unconfirmed'),
    ('a1100001-1111-4111-8111-000000000009'::uuid, 'b1100001-1111-4111-8111-000000000009'::uuid, NULL::uuid, 'demo_dataset', TIMESTAMPTZ '2026-11-08 00:00:00+00', 640, 480, NULL::numeric, NULL::text, 'D00', NULL::text, TIMESTAMPTZ '2026-11-08 00:00:00+00', true, 'unconfirmed'),
    ('a1100001-1111-4111-8111-000000000010'::uuid, 'b1100001-1111-4111-8111-000000000010'::uuid, NULL::uuid, 'demo_dataset', TIMESTAMPTZ '2026-11-08 00:00:00+00', 1024, 768, NULL::numeric, NULL::text, 'D10', NULL::text, TIMESTAMPTZ '2026-11-08 00:00:00+00', true, 'unconfirmed')
  ) AS seed (
    id, capture_id, organization_id, source, captured_at,
    image_width, image_height, priority_score, priority_label,
    anomaly_type, model_bundle_version, created_at, is_demo, status
  )
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN current_database() IS DISTINCT FROM 'tariqmap_dev_local'
        OR (
          inet_server_addr() IS NOT NULL
          AND host(inet_server_addr()) NOT IN ('127.0.0.1', '::1')
        )
        OR COALESCE(current_setting('cluster_name', true), '') ILIKE '%supabase%'
        OR (
          SELECT count(*)
          FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'observations'
            AND column_name IN (
              'priority_score', 'model_bundle_version', 'organization_id'
            )
            AND is_nullable = 'YES'
        ) IS DISTINCT FROM 3
      THEN (SELECT 1 / 0)
      ELSE 1
    END AS allowed
  ) AS guard
  WHERE guard.allowed = 1
    AND NOT EXISTS (
      SELECT 1 FROM public.observations existing WHERE existing.id = seed.id
    );
END
$seed$;

COMMIT;
