pluginManagement {
    val flutterSdkPath =
        run {
            val localProperties = file("local.properties")
            val localPropertiesText = localProperties.readText(Charsets.UTF_8)
            val properties = java.util.Properties()
            localPropertiesText.reader().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            // Flutter's Gradle plugins re-read this generated, ignored file
            // through java.util.Properties' ISO-8859-1 byte API. Normalize raw
            // non-ASCII text to Java unicode escapes before that second read.
            if (localPropertiesText.any { it.code > 0x7f }) {
                val normalized =
                    buildString {
                        localPropertiesText.forEach { character ->
                            if (character.code > 0x7f) {
                                append("\\u")
                                append(character.code.toString(16).padStart(4, '0'))
                            } else {
                                append(character)
                            }
                        }
                    }
                localProperties.writeText(normalized, Charsets.ISO_8859_1)
            }
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
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
