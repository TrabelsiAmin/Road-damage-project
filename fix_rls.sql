-- Run this script in the Supabase SQL Editor to allow the mobile app to sync data anonymously.

-- 1. Observations
CREATE POLICY "Enable insert for anonymous users" 
ON "public"."observations"
AS PERMISSIVE FOR INSERT
TO anon
WITH CHECK (true);

-- 2. Locations
CREATE POLICY "Enable insert for anonymous users" 
ON "public"."locations"
AS PERMISSIVE FOR INSERT
TO anon
WITH CHECK (true);

-- 3. Agent Runs
CREATE POLICY "Enable insert for anonymous users" 
ON "public"."agent_runs"
AS PERMISSIVE FOR INSERT
TO anon
WITH CHECK (true);

-- 4. Detections
CREATE POLICY "Enable insert for anonymous users" 
ON "public"."detections"
AS PERMISSIVE FOR INSERT
TO anon
WITH CHECK (true);

-- 5. Sync Receipts
CREATE POLICY "Enable insert for anonymous users" 
ON "public"."sync_receipts"
AS PERMISSIVE FOR INSERT
TO anon
WITH CHECK (true);
