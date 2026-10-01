pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

// HaishinKit.kt is vendored under third_party/HaishinKit.kt (see its
// PATCH_NOTES.md) rather than fetched from JitPack — see app/build.gradle.kts
// for why. These two modules mirror upstream's own :haishinkit/:rtmp Gradle
// modules, just relocated to live inside this repo.
include(":haishinkit")
project(":haishinkit").projectDir = file("../third_party/HaishinKit.kt/haishinkit")
include(":rtmp")
project(":rtmp").projectDir = file("../third_party/HaishinKit.kt/rtmp")
