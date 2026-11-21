group = "com.emirkanacar.sms_consent_kit"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.3.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.emirkanacar.sms_consent_kit"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // SMS User Consent API (SmsRetriever.startSmsUserConsent).
    implementation("com.google.android.gms:play-services-auth-api-phone:18.3.1")
    // GoogleApiAvailability for the Play Services check. This library sets minSdk 24.
    implementation("com.google.android.gms:play-services-base:18.11.1")
    // ContextCompat.registerReceiver(..., RECEIVER_EXPORTED).
    // Intentionally old: 1.15+ forces consumers onto compileSdk 35+, 1.19 onto 37.
    // These are lower bounds; Gradle picks a newer version if the app brings one.
    implementation("androidx.core:core:1.13.1")
    // Pigeon-generated code uses suspend functions and Dispatchers.Main.
    // Kept low for compatibility with older Kotlin versions.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}
