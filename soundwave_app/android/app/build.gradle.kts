import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (issue #94). CI writes android/key.properties from the
// ANDROID_KEYSTORE_* secrets; without it, release builds are debug-signed so
// they still install for testing.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.exists()) {
            keystorePropertiesFile.inputStream().use { load(it) }
        }
    }
val hasReleaseKeystore = keystorePropertiesFile.exists()

android {
    namespace = "com.pxalabs.soundwave"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pxalabs.soundwave"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // libsoundwave.so (issue #87): the C DSP core is built by the NDK for
        // every packaged ABI (the Flutter plugin restricts ABIs to its target
        // platforms: arm64-v8a, armeabi-v7a, x86_64) and loaded from Dart via
        // DynamicLibrary.open("libsoundwave.so").
        externalNativeBuild {
            cmake {
                arguments +=
                    listOf(
                        "-DSW_BUILD_TESTS=OFF",
                        "-DSW_BUILD_BENCHMARKS=OFF",
                        "-DSW_FUZZ_SMOKE=OFF",
                        "-DANDROID_ARM_NEON=ON",
                    )
                targets += listOf("soundwave_shared")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../../native/CMakeLists.txt")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKeystore) {
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
