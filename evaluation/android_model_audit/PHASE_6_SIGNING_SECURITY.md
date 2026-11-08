# Phase 6 signing and security

No production keystore was created. No password was written into Gradle or into a tracked properties file. The release APKs and the AAB from this phase are signed with the local Android debug certificate. That is not a Play upload signature.

## Signing

Problem. Release was always the debug key, with no way to point Gradle at an upload key without hardcoding it.

Root cause. `buildTypes.release.signingConfig` was fixed to `debug`.

Files.

- `app/android/app/build.gradle.kts` — reads the environment first, then `app/android/key.properties` (`rootProject.file("key.properties")`). All four values must be non-blank or the release build type stays on `signingConfigs.debug`.
- `app/android/key.properties.example` — empty placeholders only:

```
storeFile=
storePassword=
keyAlias=
keyPassword=
```

- `app/.gitignore` — ignores `/android/key.properties`, `/android/**/*.jks`, `/android/**/*.keystore`. `app/android/.gitignore` already ignored `key.properties` and `*.jks`. `git check-ignore` matches `app/android/key.properties` and `app/android/upload-keystore.jks`. It does not ignore `key.properties.example`.

Environment names that override the file: `STORE_FILE`, `KEY_ALIAS`, `STORE_PASSWORD`, `KEY_PASSWORD`.

### Proof the missing key would be used

Command, from `app/android`, with `STORE_FILE=/tmp/phase6-missing-upload.jks`, `KEY_ALIAS=upload`, and both passwords set to the literal placeholder word:

- `:app:signingReport` succeeded and printed `Config: release`, `Store: /tmp/phase6-missing-upload.jks`, `Alias: upload`.
- `:app:validateSigningRelease` failed: `Keystore file '/tmp/phase6-missing-upload.jks' not found for signing config 'release'.`

Those variables were not left set for the package builds.

### Proof the unset path still builds

With the four variables unset and no `key.properties` on disk, `:app:signingReport` lists only the debug config (`Store: /home/ubuntu/.android/debug.keystore`, `Alias: AndroidDebugKey`). The later `flutter build apk --release --split-per-abi` and `flutter build appbundle --release` succeeded.

`apksigner verify --print-certs` on `app-arm64-v8a-release.apk`:

- DN: `C=US, O=Android, CN=Android Debug`
- SHA-256: `b4997d024925af75e4fd201efd278380a727d01486fa3c586e6e670c67996382`

That matches the Phase 5 debug certificate. Status: VERIFIED. Debug signing and the optional upload-key path are separate. This machine did not sign with a production key.

## Play Console upload key (do this on the Mac, not here)

1. On the machine that will upload, create an upload keystore with `keytool` and store the file outside the repo or under `app/android/` with a `.jks` name. Do not commit it.
2. Copy `app/android/key.properties.example` to `app/android/key.properties`. Set `storeFile` to that keystore path, plus `keyAlias`, `storePassword`, and `keyPassword`. Or export `STORE_FILE`, `KEY_ALIAS`, `STORE_PASSWORD`, and `KEY_PASSWORD`. Leave the example file empty.
3. Enroll in Play App Signing. The upload key signs the AAB. Google holds the app signing key. If the upload key is lost, reset it in Play Console. Do not put the app signing key in this repo.
4. `flutter build appbundle --release`. Confirm `apksigner` or Play's pre-launch report shows the upload certificate, not `CN=Android Debug`.
5. Upload `app/build/app/outputs/bundle/release/app-release.aab` in a testing track before production.

The AAB built in this phase must not be uploaded as a production artifact. It is debug-signed.

## Security re-check

Kind: static analysis of the manifest source and of the merged arm64 release APK (`aapt dump permissions`, `aapt dump xmltree`). No device install.

| Check | Result | Status |
| --- | --- | --- |
| `android:debuggable` on release | absent. Present only on the debug APK (`application-debuggable`) | VERIFIED |
| `allowBackup` | false in source and in the release binary manifest | VERIFIED |
| `usesCleartextTraffic` | false in source and in the release binary manifest | VERIFIED |
| `RECORD_AUDIO` | removed with `tools:node="remove"`. Not in the merged release permission list. Camera still uses `enableAudio: false` | VERIFIED |
| Camera, location | `CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` kept. Camera feature `required=false` | VERIFIED |
| Gallery / video on API 24–28 | `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` maxSdk 28 kept | VERIFIED |
| `ACCESS_NETWORK_STATE`, `WAKE_LOCK` | still merged from Flutter / connectivity | VERIFIED |
| `http://` in `app/lib` | none | VERIFIED |
| Secrets in Gradle or the example file | placeholders empty. No keystore file in the tree | VERIFIED |
| `debugPrint` | error and pipeline lines (observation id, detection count, inference timing). No key material found in those calls. Not changed | VERIFIED as a scan, not a runtime log capture |
| Production Supabase | not contacted, not edited | NOT APPLICABLE |
| Network security config XML | none added. Cleartext is already disabled on the application tag | NOT APPLICABLE |

No confirmed new defect. Nothing in the manifest was edited in this phase.

Debug `kernel_blob.bin` can still contain the debug-only anon fallback because `kDebugMode` builds do. That blob is not in the release APK or the AAB. The release `libapp.so` was not re-scanned for a pasted JWT in this phase; Phase 5's finding (the word `service_role` next to a refusal check, not a JWT) was not reopened and no new secret was added to source.
