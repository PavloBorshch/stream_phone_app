plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.stream_phone_cam"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications, which uses java.time APIs
        // that minSdk 24 does not carry natively.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.stream_phone_cam"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // JVM unit tests for the pure-Kotlin parts (NetworkQualityController's
    // tuning law). Run with `./gradlew :app:testDebugUnitTest` — `flutter test`
    // does not run these.
    testImplementation("junit:junit:4.13.2")

    // Native RTMP/RTMPS publisher (PLAN.md §1.5 "Leg B"). Verified 2026-08-23:
    // HaishinKit.kt ships `haishinkit` (capture/encode/mixing) and `rtmp`
    // modules only — unlike HaishinKit.swift there is no SRT module on
    // Android, so `srt://` destinations are rejected on this platform until
    // libsrt is bridged directly (PLAN.md §3.2).
    implementation("com.github.HaishinKit.HaishinKit~kt:haishinkit:0.18.2")
    implementation("com.github.HaishinKit.HaishinKit~kt:rtmp:0.18.2")

    // PLAN.md §1.5 "Leg A" (phone -> paired PC video over the existing
    // WebRTC data connection): WebRtcCameraOutput.kt builds an org.webrtc
    // VideoSource/VideoTrack directly, fed from HaishinKit's MediaMixer. The
    // flutter_webrtc plugin project depends on this same artifact/version
    // internally, but only as `implementation`, so it isn't visible to this
    // module transitively — this is a plain direct dependency on the exact
    // same artifact, not a patch (compare third_party/flutter_webrtc's own
    // android/build.gradle, which pins the same version).
    implementation("io.github.webrtc-sdk:android:144.7559.09")
}
