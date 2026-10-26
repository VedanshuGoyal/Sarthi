// MOJUD: rewritten for AGP 9 / built-in Kotlin. The published 3.0.2 build
// file (Groovy, AGP 7.3) calls getDefaultProguardFile("proguard-android.txt"),
// which AGP 9 rejects, and minifies the library itself. Everything else —
// the Kotlin sources and the IntentSDK dependency — is upstream's, unchanged.
group = "com.phonepe.phonepe_payment_sdk"
version = "2.0.3"

plugins {
    id("com.android.library")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

android {
    namespace = "com.phonepe.phonepe_payment_sdk"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        minSdk = 21
        // The app's R8 pass keeps PhonePe's classes.
        consumerProguardFiles("proguard-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }
}

dependencies {
    implementation("phonepe.intentsdk.android.release:IntentSDK:5.2.0")
}
