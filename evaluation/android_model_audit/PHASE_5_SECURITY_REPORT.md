# Phase 5 Android security report

No production credential was created or printed. No service-role secret was added to the app. Production Supabase was not contacted.

## Manifest

| Check | Before | After this phase |
| --- | --- | --- |
| Camera | declared, hardware not required | unchanged |
| Internet | declared | unchanged. Sync needs HTTPS |
| Location | fine and coarse | unchanged |
| `RECORD_AUDIO` | merged from the camera plugin | removed with `tools:node="remove"`. Live capture uses `enableAudio: false` and there is no video recording call |
| Storage | `READ_EXTERNAL_STORAGE`, and `WRITE_EXTERNAL_STORAGE` with `maxSdkVersion` 28 | kept. Gallery import and saving a stitched video still use them on API 24–28 |
| Network state and wake lock | merged from Flutter / connectivity | kept |
| `debuggable` | true on the debug APK | still true on debug. The arm64 release APK is not marked debuggable |
| `allowBackup` | default true | `false` on debug and release artifacts |
| Cleartext | unset | `usesCleartextTraffic="false"` on debug and release artifacts |
| Custom network security config | none | none. The attribute is the policy |

`minSdk` 24 and `targetSdk` 36 mean cleartext is already off by platform default. The attribute makes that explicit for every build type, including debug. The app's Supabase URL is HTTPS. A local HTTP backend would not be allowed. That matches the production client. Debug Flutter tooling does not use the app's cleartext flag for the observatory.

## Secrets

| Build | Project ref `lendqcjihusqkmxansbl` | `eyJ` JWT prefix | word `service_role` |
| --- | --- | --- | --- |
| Debug `kernel_blob.bin` | present | present | present |
| Release `libapp.so` | absent | absent | present as the role name the client refuses |

The debug kernel contains the existing debug-only anon fallback. Release tree-shaking dropped that literal. The `service_role` hit in `libapp.so` sits in the string table beside the refusal check (`...service_role...`), not beside a JWT. No service-role key was found.

Env overrides remain `--dart-define=SUPABASE_URL` and `SUPABASE_ANON_KEY`. A release build without them still fails `assertPublicConfig` without logging the key. That Phase 3 behavior was not changed.

## What was not changed

- RLS and storage policies. The recommended SQL file is still unapplied.
- The `submit_observation` migration. It is still not deployed.
- Backend environment variables.
- `ios/`.

## Status

| Item | Status |
| --- | --- |
| Release artifact flags and the secret scan | VERIFIED by `aapt` and byte search |
| No service-role key in the release binary | VERIFIED for this scan |
| Debug anon fallback still in the debug kernel | VERIFIED. Intentional |
| Runtime permission prompts and backup behavior on a phone | NOT EXECUTED |
| RLS | NOT VERIFIED. Not changed |
