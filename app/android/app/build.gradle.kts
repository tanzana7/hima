import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Discord's mobile redirect URI is `discord-<client id>:/authorize/callback`, so
// the intent filter needs the client id at build time. Flutter passes
// `--dart-define` values to Gradle as base64 encoded `-Pdart-defines=...`, so the
// same DISCORD_CLIENT_ID the Dart code reads is reused here; a `discordClientId`
// Gradle property works as an override.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.filter { it.isNotBlank() }
        ?.mapNotNull { entry ->
            val decoded = String(Base64.getDecoder().decode(entry))
            val separator = decoded.indexOf('=')
            if (separator <= 0) {
                null
            } else {
                decoded.substring(0, separator) to decoded.substring(separator + 1)
            }
        }
        ?.toMap()
        .orEmpty()

val discordClientId: String =
    (project.findProperty("discordClientId") as String?)
        ?: dartDefines["DISCORD_CLIENT_ID"]
        ?: ""

android {
    namespace = "jp.atsumaro.atsumaro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "jp.atsumaro.atsumaro"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // `discord-unset` keeps a build without a client id (the mock demo)
        // working; the browser callback simply cannot come back to the app.
        manifestPlaceholders["discordCallbackScheme"] =
            if (discordClientId.isEmpty()) {
                "discord-unset"
            } else {
                "discord-$discordClientId"
            }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 自動ひま提案 runs its periodic check as a plain (non-foreground) WorkManager job and
    // reacts to a notification tap with core's NotificationCompat/PendingIntent helpers.
    implementation("androidx.work:work-runtime-ktx:2.12.0")
    implementation("androidx.core:core:1.13.1")
}

