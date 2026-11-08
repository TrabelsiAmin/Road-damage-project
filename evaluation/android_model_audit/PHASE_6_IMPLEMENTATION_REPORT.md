# Phase 6 implementation report

HEAD stayed `cd7d16898465174c06a1362953c052f156e0485b`. Nothing was committed or pushed. Phase 1–5 edits were left in the working tree. Files that this phase expected to edit were copied first to `evaluation/android_model_audit/backups/phase6/` (`settings.gradle.kts`, `app-build.gradle.kts`, `gradle.properties`, `pubspec.yaml`, `android.gitignore`, `AndroidManifest.xml`). `gradle.properties` and `AndroidManifest.xml` were not changed again in this phase.

Model files were not rewritten. After the edits and the rebuilds:

| File | SHA-256 | Bytes |
| --- | --- | --- |
| `app/assets/models/road_damage.tflite` | `830f99bd8c31c5d24138c16db7862dfb62293b96cc1dec241c36140bff8a813f` | 44,768,844 |
| `app/assets/models/road_damage_roadsense.tflite` | `300798be883a7003a1a20f3d13757f9338a8cbec5e0ece9f990a2a5179286ccb` | 37,347,282 |

Those are the same digests recorded at the start of this phase and in `ModelConfig`.

## What changed

### Model packaging

Problem. `pubspec.yaml` listed both `assets/models/` and an extra explicit line for `road_damage_roadsense.tflite`.

Root cause. The directory entry already includes every file in that folder. The extra line was redundant. Zip inspection of the Phase 5 artifacts, and of the Phase 6 rebuilds, showed each model once. Flutter was not packaging the same bytes twice.

Files. `app/pubspec.yaml`.

Fix. The assets section is only:

```yaml
assets:
  - assets/models/
```

The default model was not changed. Both files stay in the asset directory. See `PHASE_6_SIZE_OPTIMIZATION.md` for the measured sizes. Removing the line did not shrink the model entries.

### Loader test

Problem. There was no test that the default loader's asset path is the file on disk.

Root cause. Model selection is a compile-time flag. A missing or swapped file would still compile.

Files. `app/test/unit/model_asset_test.dart` (new).

Fix. The test asserts `USE_ROADSENSE_MODEL` is off, `ModelConfig.active` is `road_damage` at `assets/models/road_damage.tflite`, and both on-disk files match the checksums the loader already stores. It does not open an interpreter and does not change the default.

Tests. `flutter test` — 149 passed, including this one. Status: VERIFIED as a unit test. It is not a device test.

### Kotlin 2.3.20

Problem. Flutter 3.47.9 warned that Kotlin 2.2.20 should be at least 2.3.20.

Root cause. `app/android/settings.gradle.kts` pinned `org.jetbrains.kotlin.android` to 2.2.20. Flutter's own checker (`DependencyVersionChecker.kt`) warns below 2.3.20 and errors below 2.2.20. The same Flutter version's `validateAgpAndKgp` allows Kotlin 2.3.10–2.3.29 with AGP 8.2.2 through 9.2.99 (exclusive max) and Gradle 7.6.3 through 9.5.99 (exclusive max). This project is AGP 8.11.1 and Gradle 8.14, so 2.3.20 is inside those tables. Flutter, AGP, Gradle, and `tflite_flutter` 0.11.0 were not upgraded.

Files. `app/android/settings.gradle.kts`, `app/android/app/build.gradle.kts`.

Fix. The Kotlin plugin version is `2.3.20`. The first build failed in script compilation: Kotlin 2.3 treats `kotlinOptions { jvmTarget = "17" }` as an error and told us to use the compilerOptions DSL. The same failure listed deprecated `aaptOptions` as a second script error. The app module now sets:

```kotlin
kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}
```

and `androidResources { noCompress += listOf("tflite", "lite") }`. The JVM target is still 17. The Phase 5 `afterEvaluate` block that forces every other Android module (including `tflite_flutter`) to Java 17 and Kotlin JVM 17 is unchanged. `isMinifyEnabled` and `isShrinkResources` stay false.

Tests. Debug APK, split release APKs, and the AAB all built. Logs have no `Inconsistent JVM` and no `source value 8`. The sentence `Kotlin version (2.2.20)` is gone. Flutter now warns that Gradle 8.14.0 should be at least 9.1.0 and AGP 8.11.1 should be at least 9.0.1. Those were left alone. Flutter's error floor is exactly this AGP and this Gradle wrapper, so a blind bump was not a safe subset. Status: VERIFIED for the Kotlin plugin bump. The new Gradle and AGP warnings are documented and not treated as a failed build.

### Release signing selection

Problem. Release builds were hardcoded to the debug signing config.

Root cause. There was no upload-key path that could be filled without putting a password in the Gradle file.

Files. `app/android/app/build.gradle.kts`, `app/android/key.properties.example` (new), `app/.gitignore`. `app/android/.gitignore` already ignored `key.properties` and `*.jks`.

Fix. Release signing is used only when `STORE_FILE` / `KEY_ALIAS` / `STORE_PASSWORD` / `KEY_PASSWORD` (environment) or `storeFile` / `keyAlias` / `storePassword` / `keyPassword` (gitignored `app/android/key.properties`) are all non-blank. Environment wins over the file. Empty placeholders do not count. Otherwise the release build type keeps `signingConfigs.debug`. No keystore was generated. Details and the two Gradle checks are in `PHASE_6_SIGNING_SECURITY.md`. Status: VERIFIED by `signingReport`, `validateSigningRelease`, and `apksigner` on the rebuilt arm64 release APK.

### Security

No new manifest defect. `allowBackup=false`, `usesCleartextTraffic=false`, and the `RECORD_AUDIO` removal from Phase 5 are still in the merged release APK. Camera, location, and the storage permissions used for gallery and video on old API levels are still there. No production Supabase change. Status: VERIFIED as a static re-check. See the signing and security report.

### What was not changed

R8 and resource shrinking stay off. ABI filters were not added. Neither TFLite model was deleted. Stretch, class codes, weights, datasets, `ios/`, and production SQL were not touched. FFmpeg and the armeabi-v7a neon copies were left in place. AAB native debug symbols were left in place. They are Play symbolication metadata, not a second copy of the installed library.

## Regression

| Suite | Result | Status |
| --- | --- | --- |
| `flutter analyze` | No issues found | VERIFIED |
| `flutter test` | 149 passed (148 from Phase 5 plus the new asset test) | VERIFIED |
| Python `unittest` (contracts, API validation, sync recovery, offline recovery, SQL contract, EXIF orientations) | 36 passed | VERIFIED |
| `lock_android_contract.py` | CONTRACT OK | VERIFIED |
| `spec_decoder_math.py` | SPEC MATH OK | VERIFIED |
| Dashboard `vitest` | 93 passed | VERIFIED |
| Dashboard `vite build` | built | VERIFIED |
| `flutter build apk --debug` | exit 0 | VERIFIED |
| `flutter build apk --release --split-per-abi` | exit 0 | VERIFIED |
| `flutter build appbundle --release` | exit 0 | VERIFIED |
| Emulator / device | not run | BLOCKED (`/dev/kvm` not writable; this is not a Mac) |
| Live Supabase tests | not run | NOT APPLICABLE. They must not hit production |
| Production SQL | not run | NOT APPLICABLE |

No test was disabled or skipped to get these results.
