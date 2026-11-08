import com.android.build.gradle.BaseExtension
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun signingValue(vararg names: String): String? {
    for (name in names) {
        val fromEnv = System.getenv(name)?.trim().orEmpty()
        if (fromEnv.isNotEmpty()) return fromEnv
        val fromFile = keystoreProperties.getProperty(name)?.trim().orEmpty()
        if (fromFile.isNotEmpty()) return fromFile
    }
    return null
}

val releaseStoreFile = signingValue("STORE_FILE", "storeFile")
val releaseKeyAlias = signingValue("KEY_ALIAS", "keyAlias")
val releaseStorePassword = signingValue("STORE_PASSWORD", "storePassword")
val releaseKeyPassword = signingValue("KEY_PASSWORD", "keyPassword")
val hasReleaseKeystore = listOf(
    releaseStoreFile,
    releaseKeyAlias,
    releaseStorePassword,
    releaseKeyPassword,
).all { !it.isNullOrEmpty() }

// tflite_flutter sets Java 1.8 and does not set a Kotlin JVM target, so Kotlin
// followed the JDK (21) and Gradle rejected the mismatch. Every Android module,
// including that plugin, compiles Java and Kotlin for the same target as this
// app. Plugin versions are unchanged. Minify stays off: R8 can strip TFLite JNI.
rootProject.subprojects
    .filter { it.path != ":app" }
    .forEach { sub ->
        sub.afterEvaluate {
            sub.extensions.findByType(BaseExtension::class.java)?.compileOptions?.apply {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
            sub.tasks.withType(KotlinCompile::class.java).configureEach {
                compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
            }
        }
    }

android {
    namespace = "com.example.tariqmap"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tariqmap.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    androidResources {
        noCompress += listOf("tflite", "lite")
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                keyAlias = releaseKeyAlias
                storePassword = releaseStorePassword
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // A filled key.properties or STORE_FILE/KEY_ALIAS/STORE_PASSWORD/KEY_PASSWORD
            // selects the upload key. With none of those set, this machine signs with
            // the debug certificate so the release build still runs. That is not a
            // Play Store signature.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // ABI-specific APKs come from `flutter build apk --split-per-abi`.
    // The App Bundle still contains every ABI; Play delivers one.
    // Do not set abiFilters here.
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
