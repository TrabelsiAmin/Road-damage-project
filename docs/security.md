# TariqMap Security Architecture & Threat Model

## 1. Credentials & Git History Audit

A full cryptographic audit of the working tree and the complete Git history was conducted on October 13, 2026:
- **Service-Role Key Status**: **Clean**. No `service_role` secret, database administrative password, or JWT secret has ever been committed to the repository history.
- **Commit `2db95009` Verification**: Although the commit message stated *"Bypass RLS using service_role key for testing"*, analysis of the committed JWT payload confirmed that the token committed had `role: "anon"`. No elevated service-role key was committed.
- **Working Tree Environment**: The backend configuration file `backend/.env` (which holds server-side secrets) is excluded by `.gitignore` and is uncommitted.
- **Client Bundles**: The mobile client (`app/lib/core/supabase_config.dart`) embeds exclusively the public `anon` JWT.
- **Audit Verification**: The Phase 0 live database audit was performed using solely the public `anon` key (`SupabaseCfg.anonKey`) via the standard PostREST HTTP interface.

---

## 2. Public Repository Threat Model & Current RLS Vulnerabilities

Because TariqMap is an open-source public repository, the Supabase project URL and the public `anon` API key are publicly readable by anyone. Under this assumption, the following current RLS policies represent security vulnerabilities:

### A) Permissive `anon` UPDATE Policies
- **`anon_update_observations`**: Allows any anonymous client possessing the public key to modify existing observation records, including tampering with `priority_score`, `priority_label`, and geographical locations.
- **`anon_update_live_sessions`**: Allows anonymous actors to modify session states, durations, or inject malicious video URLs into institutional scanning logs.

### B) Unrestricted Storage Uploads
- **`anon_upload_observation_images`** & **`anon_upload_session_videos`**: The current storage policies allow any anonymous client to upload binary files up to the bucket limit (10 MB for images, 500 MB for videos). A malicious actor could script bulk uploads to exhaust Supabase storage limits or host arbitrary content.

### C) Public Readability of Real Field Imagery
- Before Phase 5 (on-device face blurring) is fully deployed, field imagery captured on public roads may contain visible faces or vehicle license plates. Making all images publicly downloadable without institutional authorization creates GDPR and privacy risks for citizens.

---

## 3. RLS Hardening Strategy (Migration `20261013_security_and_phase1.sql`)

1. **Separate Citizen/Inspector Ingest from Authority Operations**:
   - `anon` role is strictly restricted to **INSERT** on `observations`, `locations`, `detections`, and media logs.
   - `anon` **UPDATE** and **DELETE** on `observations` are revoked.
   - For `live_sessions`, `anon` is permitted to update `frame_count`, `anomaly_count`, and `status = 'completed'` only on sessions matching the active session ID, or session finalization is routed through an authenticated role.
2. **Authority Authentication via Supabase Auth**:
   - Dashboard users authenticate via email/password (`authenticated` role).
   - Only `authenticated` users with institutional roles (`Municipality`, `Ministry of Equipment`, `Tunisia Autoroutes`) can update observation `status` (`'scheduled'`, `'repaired'`, `'verified'`).
3. **Sensitive Photo Access**:
   - Observations flagged as `is_demo = true` are public for testing and demonstration.
   - Real field photos (`is_demo = false`) are restricted to `authenticated` dashboard sessions or signed download URLs until automated face and privacy redaction is active.

---

## 4. Known Open Limitations & Accepted Risks

| Risk | Impact | Why It Remains Open | Hackathon Mitigation |
| :--- | :--- | :--- | :--- |
| **Anonymous Ingest Spam** | Malicious clients could flood fake pothole reports. | The core value proposition of TariqMap is **offline-first citizen and municipal reporting** without requiring personal user registrations. | Validate inputs (GPS coordinate bounding box within Tunisia, reasonable bounding box sizes, schema constraints). Rate-limit IP addresses at Cloudflare edge. |
| **Spoofed Device IDs** | Sybil attacks where one phone pretends to be many devices to inflate crowd confirmation. | Hardware-backed cryptographic attestation (Google Play Integrity API) requires enterprise certificates and cannot run in simulated testing environments. | Use an installation UUID stored in `SharedPreferences`. In Phase 2 crowd confirmation, flag anomalous clusters originating from identical subnets or identical timestamps. |
| **Storage Denial-of-Service** | Unauthenticated uploads could consume bucket bandwidth. | Storage bucket requires direct client upload to avoid routing 10+ MB payloads through intermediate application servers. | Restrict MIME types (`image/webp`, `image/jpeg`), enforce 5 MB cap on image files, and configure automated lifecycle clean-up on orphaned media. |
