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

// Release signing: reads android/key.properties (gitignored — never commit a
// keystore or its passwords). Falls back to the debug key when the file is
// absent, so a fresh checkout still builds; `flutter build apk --release`
// for real distribution requires generating a keystore first, see
// server/../README or `flutter build apk --release --help`.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.sarthi.user_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs java.time on older Androids.
        isCoreLibraryDesugaringEnabled = true
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

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Real release keystore once key.properties exists (see deploy docs);
            // debug keys otherwise, so a fresh checkout still builds.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Push notifications (Firebase Cloud Messaging) need android/app/
// google-services.json, downloaded from the Firebase console. It's
// git-ignored; without it the app still builds and just runs without push.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
