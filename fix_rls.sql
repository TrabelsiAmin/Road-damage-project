-- Run this script in the Supabase SQL Editor to allow the map to read data anonymously.

-- ==========================================
-- SELECT POLICIES (Required for the Map Dashboard)
-- ==========================================

CREATE POLICY "Enable read for anonymous users" ON "public"."observations" AS PERMISSIVE FOR SELECT TO anon USING (true);
CREATE POLICY "Enable read for anonymous users" ON "public"."locations" AS PERMISSIVE FOR SELECT TO anon USING (true);
CREATE POLICY "Enable read for anonymous users" ON "public"."detections" AS PERMISSIVE FOR SELECT TO anon USING (true);
