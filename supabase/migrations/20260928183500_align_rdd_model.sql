-- Align the TariqMap catalog with the bundled oracl4/RoadDamageDetection model.
-- Keep legacy classes for historical compatibility, while allowing the new
-- single on-device agent to own the four classes it produces.

ALTER TABLE public.detection_classes
  DROP CONSTRAINT IF EXISTS detection_classes_agent_check;

ALTER TABLE public.detection_classes
  ADD CONSTRAINT detection_classes_agent_check
  CHECK (agent = ANY (ARRAY['cracks'::text, 'pavement'::text, 'surface'::text, 'road_damage'::text]));

UPDATE public.detection_classes
SET agent = 'road_damage',
    work_package = CASE code
      WHEN 'D00' THEN 'RDD2022'
      WHEN 'D10' THEN 'RDD2022'
      WHEN 'D20' THEN 'RDD2022'
      WHEN 'D40' THEN 'RDD2022'
      ELSE work_package
    END
WHERE code IN ('D00', 'D10', 'D20', 'D40');

INSERT INTO public.model_versions (bundle_version, agent, checksum, format)
SELECT '2026.09.23-rdd2022', 'road_damage',
       '830f99bd8c31c5d24138c16db7862dfb62293b96cc1dec241c36140bff8a813f',
       'tflite'
WHERE NOT EXISTS (
  SELECT 1 FROM public.model_versions
  WHERE bundle_version = '2026.09.23-rdd2022'
    AND agent = 'road_damage'
);
