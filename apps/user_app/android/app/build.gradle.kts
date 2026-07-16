import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Resolve the Google Maps SDK key for the manifest. Single source of truth is
// the git-ignored apps/user_app/.env (MAPS_API_KEY=...); local.properties is a
// fallback. Empty by default so a fresh checkout still builds — the map just
// won't render tiles until a key is supplied.
fun mapsKeyFrom(f: File): String? =
    if (f.exists()) Properties().apply { f.inputStream().use { load(it) } }
        .getProperty("MAPS_API_KEY")?.takeIf { it.isNotBlank() }
    else null

// rootProject is android/; the app's .env sits one level up at apps/user_app/.
val mapsApiKey: String =
    mapsKeyFrom(rootProject.file("../.env"))
        ?: mapsKeyFrom(rootProject.file("local.properties"))
        ?: ""

android {
    namespace = "com.sarthi.user_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sarthi.user_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Fills the com.google.android.geo.API_KEY placeholder in the manifest.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
