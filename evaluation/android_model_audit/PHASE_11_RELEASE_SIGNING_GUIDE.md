# Phase 11 release signing guide

No keystore was created in this phase. `keytool` was not run. `app/android/key.properties.example` stays empty placeholders. `app/android/key.properties` is not in the tree.

The arm64 APK and the AAB on this machine were signed `CN=Android Debug` when they were built in Phase 6/7, because the four signing values were unset. This phase did not re-sign them.

## What the Gradle file does

`app/android/app/build.gradle.kts` reads, in order, environment variables then `app/android/key.properties`:

- `STORE_FILE` or `storeFile`
- `KEY_ALIAS` or `keyAlias`
- `STORE_PASSWORD` or `storePassword`
- `KEY_PASSWORD` or `keyPassword`

All four must be non-blank or release keeps the debug signing config. Phase 6 ran `validateSigningRelease` with `STORE_FILE` pointed at a missing path and Gradle failed with `Keystore file '/tmp/phase6-missing-upload.jks' not found for signing config 'release'.` That check was not repeated this phase. The code path is unchanged.

## Create the upload key on the release machine

Do this on the Mac that will upload. Do not commit the keystore or the filled properties file.

```bash
keytool -genkeypair -v \
  -keystore "$HOME/keystores/tariqmap-upload.jks" \
  -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

`keytool` will prompt for the passwords. Do not put them in the command line and do not paste them into chat or git.

```bash
cp app/android/key.properties.example app/android/key.properties
```

Fill `storeFile` with the keystore path and fill `keyAlias`, `storePassword`, and `keyPassword`. Alternatively export `STORE_FILE`, `KEY_ALIAS`, `STORE_PASSWORD`, and `KEY_PASSWORD` for that shell only. `app/.gitignore` and `app/android/.gitignore` ignore `key.properties`, `*.jks`, and `*.keystore`.

```bash
cd app
flutter build appbundle --release
```

## Check the certificate is not the debug one

```bash
# APK, if you also built split APKs
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# AAB
unzip -p build/app/outputs/bundle/release/app-release.aab META-INF/ANDROIDD.RSA | keytool -printcert
```

The subject must be the upload key you just created. If it still says `CN=Android Debug`, the four values were not visible to Gradle. Do not upload that AAB.

Enroll in Play App Signing. Google holds the app signing key. Keep the upload keystore and both passwords in a password manager and an offline copy. Losing the upload key means a Play Console reset, not a new key committed to this repo.

The current AAB at `app/build/app/outputs/bundle/release/app-release.aab` (231,089,677 bytes) is the debug-signed build. It is not the Play artifact.
