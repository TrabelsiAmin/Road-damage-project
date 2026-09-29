-- Migration: Add media storage tables and live session tracking
-- Apply this in: Supabase Dashboard > SQL Editor
-- Or via: supabase db push

-- ============================================================
-- TABLE: media_files
-- Tracks every image/video uploaded to Supabase Storage by
-- the mobile app. Links back to the observation that triggered
-- the capture.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.media_files (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    observation_id   UUID REFERENCES public.observations(id) ON DELETE SET NULL,
    bucket           TEXT NOT NULL,           -- 'observation-images' | 'live-session-videos'
    storage_path     TEXT NOT NULL,           -- path inside the bucket
    public_url       TEXT NOT NULL,           -- CDN-accessible public URL
    media_type       TEXT NOT NULL CHECK (media_type IN ('image', 'video', 'frame')),
    mime_type        TEXT NOT NULL,           -- e.g. 'image/jpeg', 'video/mp4'
    file_size_bytes  BIGINT,
    uploaded_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast lookup by observation
CREATE INDEX IF NOT EXISTS idx_media_files_observation_id
    ON public.media_files (observation_id);

CREATE INDEX IF NOT EXISTS idx_media_files_bucket
    ON public.media_files (bucket);

-- ============================================================
-- TABLE: live_sessions
-- One row per live road-scanning session started from the app.
-- Updated in real-time as frames are processed.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.live_sessions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    started_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at       TIMESTAMPTZ,
    actor          TEXT NOT NULL,
    device_id      TEXT,
    latitude       DOUBLE PRECISION NOT NULL DEFAULT 0,
    longitude      DOUBLE PRECISION NOT NULL DEFAULT 0,
    status         TEXT NOT NULL CHECK (status IN ('recording', 'completed', 'aborted'))
                   DEFAULT 'recording',
    frame_count    INTEGER NOT NULL DEFAULT 0,
    anomaly_count  INTEGER NOT NULL DEFAULT 0,
    duration_s     INTEGER,                  -- filled on session end
    video_url      TEXT,                     -- public URL of stitched video (optional)
    updated_at     TIMESTAMPTZ DEFAULT NOW(),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_live_sessions_actor
    ON public.live_sessions (actor);

CREATE INDEX IF NOT EXISTS idx_live_sessions_status
    ON public.live_sessions (status);

-- ============================================================
-- STORAGE BUCKETS
-- Run these via Supabase Dashboard > Storage > New Bucket
-- or with the Supabase CLI:
--   supabase storage create observation-images --public
--   supabase storage create live-session-videos --public
-- ============================================================

-- Enable public access on the storage buckets
-- NOTE: These INSERT statements only work if the bucket does not already exist.
-- If you get a "duplicate key" error, the bucket already exists — that is fine.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    (
        'observation-images',
        'observation-images',
        true,
        10485760,  -- 10 MB per image
        ARRAY['image/jpeg', 'image/png', 'image/webp']
    )
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = EXCLUDED.file_size_limit;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    (
        'live-session-videos',
        'live-session-videos',
        true,
        524288000, -- 500 MB per video
        ARRAY['video/mp4', 'video/quicktime', 'video/webm']
    )
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = EXCLUDED.file_size_limit;

-- ============================================================
-- ROW LEVEL SECURITY (RLS) — PERMISSIVE FOR MOBILE INGEST
-- NOTE: PostgreSQL does not support CREATE POLICY IF NOT EXISTS.
-- We use DO $$ blocks to make these idempotent (safe to re-run).
-- ============================================================

ALTER TABLE public.media_files  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.live_sessions ENABLE ROW LEVEL SECURITY;

-- media_files: allow anon INSERT
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='media_files' AND policyname='anon_insert_media_files'
  ) THEN
    CREATE POLICY "anon_insert_media_files"
      ON public.media_files FOR INSERT TO anon WITH CHECK (true);
  END IF;
END $$;

-- media_files: allow anon SELECT
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='media_files' AND policyname='anon_select_media_files'
  ) THEN
    CREATE POLICY "anon_select_media_files"
      ON public.media_files FOR SELECT TO anon USING (true);
  END IF;
END $$;

-- live_sessions: allow anon INSERT
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='live_sessions' AND policyname='anon_insert_live_sessions'
  ) THEN
    CREATE POLICY "anon_insert_live_sessions"
      ON public.live_sessions FOR INSERT TO anon WITH CHECK (true);
  END IF;
END $$;

-- live_sessions: allow anon SELECT
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='live_sessions' AND policyname='anon_select_live_sessions'
  ) THEN
    CREATE POLICY "anon_select_live_sessions"
      ON public.live_sessions FOR SELECT TO anon USING (true);
  END IF;
END $$;

-- live_sessions: allow anon UPDATE
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='live_sessions' AND policyname='anon_update_live_sessions'
  ) THEN
    CREATE POLICY "anon_update_live_sessions"
      ON public.live_sessions FOR UPDATE TO anon USING (true);
  END IF;
END $$;

-- Storage: allow anon upload to observation-images
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects' AND policyname='anon_upload_observation_images'
  ) THEN
    CREATE POLICY "anon_upload_observation_images"
      ON storage.objects FOR INSERT TO anon
      WITH CHECK (bucket_id = 'observation-images');
  END IF;
END $$;

-- Storage: public read from observation-images
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects' AND policyname='public_read_observation_images'
  ) THEN
    CREATE POLICY "public_read_observation_images"
      ON storage.objects FOR SELECT TO anon
      USING (bucket_id = 'observation-images');
  END IF;
END $$;

-- Storage: allow anon upload to live-session-videos
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects' AND policyname='anon_upload_session_videos'
  ) THEN
    CREATE POLICY "anon_upload_session_videos"
      ON storage.objects FOR INSERT TO anon
      WITH CHECK (bucket_id = 'live-session-videos');
  END IF;
END $$;

-- Storage: public read from live-session-videos
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects' AND policyname='public_read_session_videos'
  ) THEN
    CREATE POLICY "public_read_session_videos"
      ON storage.objects FOR SELECT TO anon
      USING (bucket_id = 'live-session-videos');
  END IF;
END $$;

