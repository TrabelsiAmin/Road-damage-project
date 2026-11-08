# Phase 2 security review

No production key was rotated. No RLS or Storage SQL was executed. No secret is printed in this file.

## What the clients hold

The Flutter app and the dashboard still contain the public anon key as a fallback so a local run without env vars starts. The JWT payload role for that fallback is `anon`. It is not a service-role key. A public anon key is not treated as something to delete from the client in this pass.

Startup now refuses a key whose payload role is `service_role`, an empty URL, or an empty key. The thrown message does not include the key. Flutter `Supabase.initialize` no longer sets debug HTTP logging. Dashboard logs were not changed to print the key.

Overrides:

- Flutter: `--dart-define=SUPABASE_URL` and `--dart-define=SUPABASE_ANON_KEY`. Example placeholders: `app/dart_defines.example.json`.
- Dashboard: `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. Example placeholders were added to `dashboard/.env.example`. The existing RAG URL comment was kept.
- Backend: `TARIQMAP_SUPABASE_SERVICE_ROLE_KEY` or `SUPABASE_SERVICE_ROLE_KEY`, from the process environment only. `backend/.env.example` has a placeholder, not a real key.

A search of the client tree found no `service_role` JWT. The backend still reads that key only from the environment and does not write it into the Flutter or dashboard bundles.

## What was not done

- The anon literal is still in `supabase_config.dart` and `dashboard/src/supabase.js`. Removing it without a build-time value would stop local startup.
- RLS policies were not read from production and were not changed.
- Storage policies were not changed.
- `training/test_rls.py` was not run.
- Sync tests use an in-memory store. They overwrite the in-process key with a non-secret test string before any request helper runs, and they do not call the hosted project.

Status for the client check: PARTIALLY VERIFIED (dashboard unit tests passed; Flutter startup was not executed). Status for RLS and Storage: NOT APPLICABLE to this pass, because they were not executed.

## Recommended policies, for approval only

These are not migrations. Do not run them against production until they are reviewed on a staging project.

1. Keep the service-role key on the FastAPI host only. Do not ship it in the Flutter app, the Vite bundle, or a logged header.
2. Anon insert into `observations`, `locations`, `agent_runs`, `detections`, `sync_receipts`, and `media_files` should require an authenticated user, and the row’s user or device should match the session. A blanket anon insert lets anyone write rows if they have the public key.
3. Anon select on `observations` should keep omitting `device_id`, as the dashboard query already does. Confirm the column grant, not only the client select list.
4. `observation-images` should stay private. Reads should go through a short-lived signed URL for an authority user. `public-photos` should allow public read only for the blurred thumbnail path, not for the original.
5. `submit_observation` should honor the client UUID v5 ids or return the ids it stored. If it inserts a second row with a random id, a retry cannot see the first child and may duplicate it.
6. Do not grant anon update or delete on observations. Authority updates should stay behind `is_authority()` and should check that the updated row count is 1, which the dashboard already does.
7. After a policy change, run the RLS tests against staging. Do not point them at production from this clone.

Status of these recommendations: NOT VERIFIED. They were not applied.
