// Vendored from shogo4405/HaishinKit.kt 0.18.2 (tag 0.18.2, commit
// 7b745bcaadc9afc40413150d74d0934b00f41390) — see ../PATCH_NOTES.md.
// Same adaptation as ../haishinkit/build.gradle.kts: no maven-publish/dokka,
// no version catalog, versions copied verbatim from upstream's
// gradle/libs.versions.toml at this tag. `api(project(":haishinkit"))`
// mirrors upstream's own inter-module dependency, now pointed at the
// sibling vendored module instead of a published artifact.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.haishinkit.rtmp"
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
    api(project(":haishinkit"))
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("com.google.android.material:material:1.12.0")
}
