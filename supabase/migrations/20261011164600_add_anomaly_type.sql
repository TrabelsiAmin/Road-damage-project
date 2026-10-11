-- Store the actual road-damage class separately from the priority label.
-- The current phone model produces only D00, D10, D20, and D40.

ALTER TABLE public.observations
  ADD COLUMN IF NOT EXISTS anomaly_type TEXT;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'observations_anomaly_type_check'
  ) THEN
    ALTER TABLE public.observations
      ADD CONSTRAINT observations_anomaly_type_check
      CHECK (anomaly_type IS NULL OR anomaly_type IN ('D00', 'D10', 'D20', 'D40'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_observations_anomaly_type
  ON public.observations (anomaly_type);

-- Demo/seed observations that predate this field are distributed deterministically
-- across the four classes so the map visibly exercises every class color.
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (ORDER BY created_at ASC, id) AS row_number
  FROM public.observations
)
UPDATE public.observations AS o
SET anomaly_type = CASE ((ranked.row_number - 1) % 4)
  WHEN 0 THEN 'D00'
  WHEN 1 THEN 'D10'
  WHEN 2 THEN 'D20'
  WHEN 3 THEN 'D40'
END
FROM ranked
WHERE o.id = ranked.id
  AND o.anomaly_type IS NULL;
