# Phase 4 database validation

The migration `supabase/migrations/20261105_submit_observation_stable_ids.sql` was applied only to a disposable local database named `tariqmap_phase4` on PostgreSQL 16.15 on this machine. Production Supabase was not contacted. The file is still unapplied in the project's hosted database.

## Static review

| Check | Result |
| --- | --- |
| Signature | `submit_observation(jsonb, jsonb, jsonb, jsonb, text)` returns `jsonb`. Same argument list as `20261016_atomic_ingest_and_validation.sql` |
| Client observation id | Assigned from `p_observation->>'id'` and inserted as `observations.id`. A missing or non-UUID value raises `Invalid observation ID` before inserts |
| Capture id | Same treatment |
| Child ids | Required. Stored as the UUID the client sent. The function does not compute UUID v5 and does not call `gen_random_uuid()`. Flutter still sends UUID v5 |
| Idempotency | A key already stored for a different observation raises. The same observation returns `already_synced` when nothing new is inserted |
| Conflict | If a detection id already belongs to another observation, the call raises `detection … was not stored` and the new observation is not kept |
| Transaction | One function call. An exception leaves no new observation, child, or receipt from that call. There is no `COMMIT` in the middle |
| Receipt | `INSERT INTO public.sync_receipts` is after the existence checks for the observation, location, agent runs, and detections |
| Delete | None |
| Class check | Still only D00, D10, D20, D40. `D99` raises and rolls back |
| Null confidence or box | Now rejected. The previous draft treated NULL comparisons as success |
| Auth | `SECURITY DEFINER`, `search_path = public, pg_temp`, `GRANT EXECUTE` to `anon` and `authenticated`. The body does not call `auth.uid()`. That matches the previous function. RLS does not apply inside a security-definer function |
| Schema | Insert column lists match the previous function. This repo has no `CREATE TABLE public.observations`. Compatibility with extra production `NOT NULL` columns was not proven |

## Local execution

Roles `anon` and `authenticated` were created so the `GRANT` could run. Tables were created with the columns the function writes: `organizations`, `known_model_versions`, `observations`, `locations`, `agent_runs`, `detections`, `sync_receipts`. That harness is not a production dump.

`evaluation/android_model_audit/scripts/test_submit_observation_pg.py` refuses to run unless `PHASE4_LOCAL_PG_URL` contains `phase4`. It connected to `postgresql:///tariqmap_phase4`.

| Case | Result |
| --- | --- |
| First call | `status` `synced`, `observation_id` equals the client id |
| Second call with the same ids | `already_synced`. One observation, one agent run, one detection, and that detection id is the UUID v5 the client sent |
| Observation row inserted alone, then the function | `repaired`. One detection and one receipt. A further call stays `already_synced` and does not add a second detection |
| Observation id `not-a-uuid`, detection id `nope`, null confidence | each call errors. The observation count does not change |
| Detection id already owned by another observation | error. The new observation is absent. The existing detection still points at the original observation |
| Detection class `D99` | error. No observation and no receipt for that id |

The parser test also passed: executable SQL still has no `gen_random_uuid()` and no `DELETE`, and the receipt insert is after the detection insert.

## Status

| Item | Status |
| --- | --- |
| Local apply and the cases above | VERIFIED |
| Production schema and production data | NOT VERIFIED |
| Deploy | NOT APPLICABLE this pass. Do not apply the file to production from this clone |

Approval still required: review the migration on staging, confirm old random-id children stay, then use the normal migration path. Do not add a cleanup `DELETE` in that step.
