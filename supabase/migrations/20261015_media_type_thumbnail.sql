DO $$
DECLARE c text;
BEGIN
  SELECT conname INTO c FROM pg_constraint
   WHERE conrelid = 'public.media_files'::regclass AND contype = 'c'
     AND pg_get_constraintdef(oid) LIKE '%media_type%';
  IF c IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.media_files DROP CONSTRAINT %I', c);
  END IF;
  ALTER TABLE public.media_files ADD CONSTRAINT media_files_media_type_check
    CHECK (media_type IN ('image','video','frame','thumbnail'));
END $$;