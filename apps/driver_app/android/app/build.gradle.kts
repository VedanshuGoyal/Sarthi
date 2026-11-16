import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: reads android/key.properties (gitignored — never commit a
// keystore or its passwords). A release build without it fails: a
// debug-signed APK on apps.mojud.life can't update any install signed with
// the release key, and uninstalling to get it wipes the session. For a local,
// non-distributable release build, opt in to the debug key with
// -PallowDebugSigning=true (flutter build apk --android-project-arg
// allowDebugSigning=true, or ALLOW_DEBUG_SIGNING=1 for scripts/build-*-apk.sh).
// Debug builds and `flutter run` are unaffected.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val allowDebugSigning = findProperty("allowDebugSigning")?.toString() == "true"

// Refuse to package a release signed with the debug key unless asked to.
gradle.taskGraph.whenReady {
    val releasing = hasTask("${project.path}:packageRelease") ||
        hasTask("${project.path}:bundleRelease")
    if (releasing && !keystorePropertiesFile.exists() && !allowDebugSigning) {
        throw GradleException(
            "No android/key.properties: this release would be signed with the debug " +
                "key and could not update installs of the published app. Add the " +
                "release keystore, or pass -PallowDebugSigning=true for a local, " +
                "non-distributable build."
        )
    }
}

android {
    namespace = "com.sarthi.driver_app"
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
        applicationId = "com.sarthi.driver_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
            // The release keystore when key.properties exists; otherwise the
            // debug key, which the check above allows only on request.
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
