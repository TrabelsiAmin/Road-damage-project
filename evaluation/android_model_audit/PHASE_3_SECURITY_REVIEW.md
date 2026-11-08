# Phase 3 security review

No production key was changed. No service-role secret was printed. No production SQL was executed. Env vars and the anon key do not replace row-level security or storage policies.

## What was checked

| Surface | Finding | Status |
| --- | --- | --- |
| Service-role secret in the Flutter or dashboard client | The clients refuse a JWT whose payload role is `service_role`. They do not embed a service-role key. The backend still expects its key from the environment. | VERIFIED by source review and the dashboard config test |
| Production dashboard bundle | `vite build` JS does not contain the project ref `lendqcjihusqkmxansbl` or an `eyJ` token. The debug anon literal is behind `import.meta.env.DEV`, so the production build drops it. | VERIFIED for this build |
| The word `service_role` in that bundle | Present as the role string the startup check compares. It is not a key. | NOT a secret |
| Flutter release fallback | `SupabaseCfg` returns the hardcoded public URL and anon key only when `kDebugMode` is true. A release build without `--dart-define=SUPABASE_URL` and `SUPABASE_ANON_KEY` fails `assertPublicConfig` with an error that does not include the key. | VERIFIED by reading `app/lib/core/supabase_config.dart`. The release binary was not built. |
| Local debug workflow | `flutter run` and `vite` dev still start from the existing public anon literal when env is empty. Placeholders are in `dashboard/.env.example`, `backend/.env.example`, and `app/dart_defines.example.json`. | PARTIALLY VERIFIED. Local startup was not launched. |
| Secrets in logs | Sync errors go through the Phase 2 redaction path. Media upload errors use `redactSecrets`. The config assertion does not interpolate the key. | PARTIALLY VERIFIED by the Dart sync-plan test that a JWT-shaped token is not kept, and by source review |
| `submit_observation` | The new file is `SECURITY DEFINER` with `search_path = public, pg_temp`, same as the function it would replace. It does not add a grant. It raises if a child id is missing instead of inventing one. It does not delete. It is not applied. | NOT VERIFIED on a database |
| RLS and storage | `supabase/recommended/rls_and_storage_NOT_APPLIED.sql` is comments only. It is not under `supabase/migrations`. It says anon insert should require an authenticated user, originals stay in a private bucket, public-photos is the blurred thumbnail, and anon should not get UPDATE or DELETE. Applying that sketch without a new insert path would stop current anon ingest. | NOT VERIFIED. Not executed. |
| Dashboard authorization | The dashboard uses the anon client. This phase did not add a service-role call in the frontend. Pagination uses the same client and the same filters. | NOT VERIFIED against live policies |
| Duplicate diagnostic | In-process only. It has no network client and no write. | VERIFIED for the script as written |
| Offline simulator | In-memory. It does not upload to storage. | VERIFIED that the test file has no production client |

## Anon key

The public anon key is still in the Flutter debug fallback and in the Vite dev fallback. That key is not a service-role secret. Anyone who has it can do whatever the anon policies allow. Removing it from debug is safe only after every local and CI build injects the same public key. This phase removed it from the production Vite bundle and from Flutter release when dart-defines are absent. It did not rotate the key.

## Receipts and partial writes

The client writes the receipt after the observation and the required children, and it does not mark the local row synced when the image file is missing. That reduces a false "synced" state. It does not change who is allowed to insert. Until the new SQL is applied, the database function can still return early and can still mint a random child id if some other client omits ids. Current Flutter always sends ids and still repairs missing children after the RPC.

## Approval steps that were not taken

1. Review `supabase/migrations/20261105_submit_observation_stable_ids.sql` on staging.
2. Confirm existing random-id children are left in place. Do not add a cleanup `DELETE` in that review.
3. Apply it with the project's migration path. Do not apply it from this clone.
4. Review the recommended RLS and storage comments separately. Do not apply them until authenticated insert is the real client path.
5. Do not treat a green unit test as evidence that production policies are correct.

## Status

| Item | Status |
| --- | --- |
| No service-role secret in the frontend source or this production bundle | VERIFIED |
| Production anon literal removed from the Vite bundle | VERIFIED |
| Flutter release has no anon fallback | VERIFIED by source. Release APK BLOCKED |
| Debug anon fallback kept, documented | PARTIALLY VERIFIED |
| Log redaction | PARTIALLY VERIFIED |
| New SQL and recommended policies | NOT VERIFIED. Not executed |
| Env vars as a substitute for RLS | NOT APPLICABLE. They are not a substitute |
