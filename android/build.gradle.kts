group = "com.emirkanacar.sms_consent_kit"
version = "1.0-SNAPSHOT"

buildscript {
    // Only used when the consumer app does not already provide these plugins;
    // otherwise the app's AGP / Kotlin versions win.
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

// AGP 9 compiles Kotlin itself (built-in Kotlin) and fails if kotlin-android
// is applied as well. AGP 8, or AGP 9 with android.builtInKotlin=false, needs
// the plugin. Apps on older Flutter templates are still on AGP 8.
val agpMajorVersion = androidComponents.pluginVersion.major
val usesBuiltInKotlin =
    agpMajorVersion >= 9 &&
        (findProperty("android.builtInKotlin")?.toString()?.toBooleanStrictOrNull() ?: true)
if (!usesBuiltInKotlin) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

android {
    namespace = "com.emirkanacar.sms_consent_kit"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            // Robolectric needs merged resources and manifests.
            isIncludeAndroidResources = true
            all {
                it.outputs.upToDateWhen { false }
                it.testLogging {
                    events("passed", "skipped", "failed")
                    exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
                }
            }
        }
    }
}

// Task-based instead of the `kotlin {}` extension: that extension only exists
// when a Kotlin plugin is applied in this script's `plugins {}` block, which is
// not the case on either AGP 8 or AGP 9 here.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}

dependencies {
    // SMS User Consent API (SmsRetriever.startSmsUserConsent).
    implementation("com.google.android.gms:play-services-auth-api-phone:18.3.1")
    // GoogleApiAvailability for the Play Services check. This library sets minSdk 24.
    implementation("com.google.android.gms:play-services-base:18.11.1")
    // ContextCompat.registerReceiver(..., RECEIVER_EXPORTED), BundleCompat.
    // Intentionally old: 1.15+ forces consumers onto compileSdk 35+, 1.19 onto 37.
    // These are lower bounds; Gradle picks a newer version if the app brings one.
    implementation("androidx.core:core:1.13.1")
    // Pigeon-generated code uses suspend functions and Dispatchers.Main.
    // Kept low for compatibility with older Kotlin versions.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
    testImplementation("org.robolectric:robolectric:4.18.1")
}
