// Vendored from shogo4405/HaishinKit.kt 0.18.2 (tag 0.18.2, commit
// 7b745bcaadc9afc40413150d74d0934b00f41390) — see ../PATCH_NOTES.md.
//
// Adapted from upstream's own haishinkit/build.gradle.kts: the
// maven-publish/dokka plugins and version-catalog (`libs.xxx`) aliases are
// dropped since this is a local source module, not a published artifact,
// and this app has no `gradle/libs.versions.toml` wired in — dependency
// versions below are copied verbatim from upstream's own
// gradle/libs.versions.toml at this tag instead of resolved through one.
// Everything else (namespace, compileSdk/minSdk, compileOptions, the
// dependency list itself) is unchanged from upstream.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization") version "2.3.20"
}

android {
    namespace = "com.haishinkit"
    compileSdk = 36

    defaultConfig {
        minSdk = 21
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    buildFeatures { buildConfig = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
            )
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
}
