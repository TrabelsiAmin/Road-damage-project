-- The current Flutter app has not added Supabase Auth yet, so its backend
-- sync cannot provide an auth.users profile. Keep the column available for
-- authenticated clients, but allow this service-role ingestion path to omit it.
ALTER TABLE public.observations
  ALTER COLUMN created_by DROP NOT NULL;
