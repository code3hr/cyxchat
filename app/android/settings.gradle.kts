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
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

// Fix for plugins that use flutter.compileSdkVersion (like record_android)
// Must be configured here before subprojects are evaluated
gradle.beforeProject {
    if (name != "app" && name != rootProject.name) {
        extensions.create("flutter", FlutterExtension::class.java)
    }
}

open class FlutterExtension {
    val compileSdkVersion: Int = 35
    val minSdkVersion: Int = 21
    val targetSdkVersion: Int = 35
    val ndkVersion: String = "27.0.12077973"
}
