import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val playbackDartDefines =
    providers.gradleProperty("dart-defines").orNull
        ?.split(",")
        ?.mapNotNull { encoded ->
            runCatching {
                String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
            }.getOrNull()
        }
        ?.mapNotNull { define ->
            val separator = define.indexOf('=')
            if (separator <= 0) {
                null
            } else {
                define.substring(0, separator) to define.substring(separator + 1)
            }
        }
        ?.toMap()
        .orEmpty()
val requestedAudioEngine = playbackDartDefines["FURA_AUDIO_ENGINE"]
val requestedSystemMedia = playbackDartDefines["FURA_SYSTEM_MEDIA"]
val invalidPlaybackDefine =
    requestedAudioEngine != null &&
        requestedAudioEngine !in setOf("audioplayers", "media_kit") ||
        requestedSystemMedia != null &&
        requestedSystemMedia !in setOf("audio_service", "flutter_media_session")
val audioServiceMediaButtonReceiverEnabled =
    invalidPlaybackDefine || requestedSystemMedia == "audio_service"

val flutterAndroidAbis =
    mapOf(
        "android-arm" to "armeabi-v7a",
        "android-arm64" to "arm64-v8a",
        "android-x64" to "x86_64",
    )
val requestedAndroidAbis =
    providers.gradleProperty("target-platform").orNull?.split(",")?.map { platform ->
        flutterAndroidAbis[platform]
            ?: throw GradleException("Unsupported Flutter Android target: $platform")
    }?.toSet()

android {
    namespace = "dev.axiaobo.flutterustmusic"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.axiaobo.flutterustmusic"
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

        // AndroidX Media3 requires exactly one enabled MEDIA_BUTTON receiver.
        // Keep audio_service packaged for rollback builds, but disable its
        // receiver when the valid/default requested edge is
        // flutter_media_session. Invalid defines fail closed to rollback A in
        // Dart, so they must also enable the audio_service receiver here.
        manifestPlaceholders["audioServiceMediaButtonReceiverEnabled"] =
            audioServiceMediaButtonReceiverEnabled
        manifestPlaceholders["flutterMediaSessionMediaButtonReceiverEnabled"] =
            !audioServiceMediaButtonReceiverEnabled
        manifestPlaceholders["audioServiceSystemEdgeEnabled"] =
            audioServiceMediaButtonReceiverEnabled
        manifestPlaceholders["flutterMediaSessionSystemEdgeEnabled"] =
            !audioServiceMediaButtonReceiverEnabled
        buildConfigField(
            "boolean",
            "USE_AUDIO_SERVICE_SYSTEM_EDGE",
            audioServiceMediaButtonReceiverEnabled.toString(),
        )

        // Flutter limits its engine output to target-platform, but a transitive
        // JNI dependency can otherwise add libraries for unrelated ABIs. Keep
        // Android's compatibility metadata aligned with the complete app.
        requestedAndroidAbis?.let { abis ->
            ndk {
                abiFilters.clear()
                abiFilters.addAll(abis)
            }
        }
    }

    buildTypes {
        release {
            // TD-002: development only; do not distribute this debug-signed build.
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
