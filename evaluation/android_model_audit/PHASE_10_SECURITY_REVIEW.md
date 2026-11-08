# Phase 10 security review

Static read of the current clients and Gradle file. No secret value is printed. Production Supabase was not contacted. The SQL migration was not applied. Android was not rebuilt, so this is not a new APK scan.

| Item | What the code does | Status |
| --- | --- | --- |
| Service-role in Flutter | `assertPublicConfig` throws if the JWT role is `service_role`. The error text does not include the key | VERIFIED |
| Service-role in the dashboard | `dashboard/src/supabase.js` refuses the same role. `supabaseConfig.test.js` covers it | VERIFIED |
| Anon fallback | `SupabaseCfg.anonKey` returns the literal only when `kDebugMode` is true. Release without `SUPABASE_ANON_KEY` is empty and fails the assert. The literal's role is the public anon role, not service-role | VERIFIED as source. The debug APK can still contain that literal. Phase 7 already measured JWT-shaped bytes in the debug kernel and not in release `libapp.so` |
| Signing | `hasReleaseKeystore` requires store file, alias, and both passwords. Otherwise release uses the debug signing config. `key.properties.example` is empty. `key.properties` is not in the tree | VERIFIED as source. This phase did not re-run `apksigner` |
| Manifest | Phase 5 flags remain in the working tree: `allowBackup` false, cleartext false, `RECORD_AUDIO` removed. Not re-dumped from an APK this phase | PARTIALLY VERIFIED (source only) |
| Production SQL | `20261105_submit_observation_stable_ids.sql` is untracked and was not executed | NOT APPLICABLE |
| Recommended RLS file | `supabase/recommended/rls_and_storage_NOT_APPLIED.sql` is still not applied | NOT APPLICABLE |
| Dataset tooling | Validator and splitter do not write into the image directory | VERIFIED |

No new defect was fixed. Upload signing is still not a production certificate.
