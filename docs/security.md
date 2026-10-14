# TariqMap Security Architecture & Threat Model

## 1. Credentials & Git History Audit

A full cryptographic audit of the working tree and the complete Git history was conducted on October 13, 2026:
- **Service-Role Key Status**: **Clean**. No `service_role` secret, database administrative password, or JWT secret has ever been committed to the repository history.
- **Commit `2db95009` Verification**: Although the commit message stated *"Bypass RLS using service_role key for testing"*, analysis of the committed JWT payload confirmed that the token committed had `role: "anon"`. No elevated service-role key was committed.
- **Working Tree Environment**: The backend configuration file `backend/.env` (which holds server-side secrets) is excluded by `.gitignore` and is uncommitted.
- **Client Bundles**: The mobile client (`app/lib/core/supabase_config.dart`) embeds exclusively the public `anon` JWT.
- **Audit Verification**: The Phase 0 live database audit was performed using solely the public `anon` key (`SupabaseCfg.anonKey`) via the standard PostgREST HTTP interface.

---

## 2. Public Repository Threat Model & Hardened RLS State

Because TariqMap is an open-source public repository, the Supabase project URL and the public `anon` API key are publicly readable by anyone. Under this model, access control relies strictly on PostgreSQL Row Level Security (RLS) and column-level privileges.

### Measured Live Verification Status (Run on Live Supabase Instance)

| Security Boundary | Measured Live Behavior | Policy / Mechanism | Status |
| :--- | :--- | :--- | :--- |
| **Anon UPDATE on observations** | Blocked (`APIError: denied`) | No UPDATE policy granted to `anon` role | ✅ PASSED |
| **Anon DELETE on observations** | Blocked (`APIError: denied`) | No DELETE policy granted to `anon` or `authenticated` | ✅ PASSED |
| **Anon Storage list / read** | Blocked (`0 files visible`) | `observation-images` bucket `public = false`, RLS requires `is_authority()` | ✅ PASSED |
| **Anon INSERT with is_demo=true** | Blocked (`check violation`) | `WITH CHECK (is_demo = false AND status = 'unconfirmed')` | ✅ PASSED |
| **Anon INSERT with status != unconfirmed** | Blocked (`check violation`) | `WITH CHECK (is_demo = false AND status = 'unconfirmed')` | ✅ PASSED |
| **Device ID Anonymity** | Hidden from anonymous queries | Column privilege: `SELECT` revoked from `anon`, explicit columns granted | ✅ PASSED |
| **Storage Privacy** | Private bucket, authority read only | `observation-images` bucket `public = false`, capped at 10 MB | ✅ HARDENED |
| **Table Privilege Minimization** | Revoked excess privileges | DELETE, TRUNCATE, TRIGGER, REFERENCES revoked from public tables | ✅ HARDENED |
| **Function Execution Lockdown** | Internal functions locked | `REVOKE EXECUTE FROM PUBLIC, anon` on helper and trigger functions | ✅ HARDENED |

---

## 3. Storage Privacy & Media Architecture

1. **`observation-images` (Private)**:
   - Capped at 10 MB (`image/jpeg`, `image/webp`, `image/png`).
   - Read/download requires authenticated operator matching `is_authority()`.
   - Mobile client uploads compressed WebP frames anonymously directly via `anon_upload_observation_images`.
2. **`demo-images` (Public)**:
   - Capped at 5 MB for seed demonstration imagery.

---

## 4. Known Open Limitations & Accepted Risks

| Risk | Impact | Root Cause & Why It Remains Open | Hackathon Mitigation & Detection |
| :--- | :--- | :--- | :--- |
| **Anonymous Ingest Spam & Poisoning** | Malicious clients could flood fake pothole reports into `detections`, `locations`, `agent_runs`, and `sync_receipts`. | `anon INSERT WITH CHECK (true)` is permitted so offline-first citizen inspections can sync without mandatory user signups. | Rate-limit requests at reverse proxy / Cloudflare edge. Enforce spatial boundary checks (coordinates must lie within Tunisia: lat 30°–38°N, lng 7°–12°E). Run server-side anomaly clustering before publishing to authority triage queue. |
| **Spoofed Device IDs** | Sybil attacks where one device rotates UUIDs to inflate damage consensus. | Device IDs are client-generated UUIDs stored in local storage (`SharedPreferences`). Hardware-backed attestation (Google Play Integrity API) requires Google Play Console certificates. | Device IDs are hidden from public queries via column privileges. Multi-report clustering checks cross-device correlation and flags identical subnet / timestamp bursts. |
| **Unauthenticated Storage Upload Exhaustion** | Anon uploads could consume storage quota. | Direct client upload to Storage is required by offline-first mobile architecture. | File size caps (10 MB for images), allowed MIME type enforcement, and automated cleanup of unreferenced objects older than 7 days. |

---

## 5. Migration History Discrepancy & Reconciliation Plan

### Measured Discrepancy
- **Remote Supabase Database (`supabase_migrations.schema_migrations`)**: Holds **4 applied entries**.
- **Local Repository (`supabase/migrations/`)**: Contains **6 migration files**:
  1. `20260928183500_align_rdd_model.sql`
  2. `20260928183800_allow_unauthenticated_observation_ingest.sql`
  3. `20260929_add_anon_rls_policies.sql` (non-standard 8-digit timestamp)
  4. `20260929_add_media_and_sessions.sql` (historical, removed; non-standard 8-digit timestamp)
  5. `20261011164600_add_anomaly_type.sql`
  6. `20261013_security_and_phase1.sql` (applied via SQL Editor, not recorded in `schema_migrations`)

### Root Cause
Early database setup scripts were executed directly in the Supabase SQL Editor or had migration files named without the 14-digit `YYYYMMDDHHMMSS` format expected by `supabase db push`. Migration `20261013_security_and_phase1.sql` was applied directly, leaving the remote migration table with only 4 historical records.

### Reconciliation Procedure
1. Standardize all migration files in `supabase/migrations/` to standard 14-digit format:
   - Rename `20260929_add_anon_rls_policies.sql` -> `20260929120000_add_anon_rls_policies.sql`
   - Rename `20260929_add_media.sql` -> `20260929140000_add_media.sql`
   - Rename `20261013_security_and_phase1.sql` -> `20261013120000_security_and_phase1.sql`
2. Mark applied migrations in Supabase tracking table without re-executing DDL:
   ```bash
   supabase migration repair --status applied 20260928183500
   supabase migration repair --status applied 20260928183800
   supabase migration repair --status applied 20260929120000
   supabase migration repair --status applied 20260929140000
   supabase migration repair --status applied 20261011164600
   supabase migration repair --status applied 20261013120000
   ```
3. Apply Phase 1c migration `20261013233000_phase1c_security_hardening.sql` once confirmed by operator.
