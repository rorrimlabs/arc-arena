import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes ONLY from android/key.properties (git-ignored; never
// commit it or the keystore — docs/RELEASE.md §4). Without it a release build
// stops with instructions (below) instead of being signed with the debug key,
// which could never be updated in place and would cost the device its data.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val hasReleaseKey = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !keystoreProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "in.rorrim.arena_ops"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (java.time on older Android).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "in.rorrim.arena_ops"
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
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Never the debug key. With no release key configured the release
            // tasks are refused before anything is built (taskGraph check below).
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// The --dart-define(-from-file) values the Flutter tool passes to Gradle
// (comma-separated, each base64 "KEY=value"). Only AO_BACKEND is read here.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.mapNotNull { runCatching { String(Base64.getDecoder().decode(it)) }.getOrNull() }
        ?.mapNotNull { d -> d.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
        ?.toMap()
        ?: emptyMap()

// A release APK/AAB must be cloud-only and carry the release key: fail fast,
// before anything is built, and say what to do. (Debug/profile are untouched.)
gradle.taskGraph.whenReady {
    val releaseTask = allTasks.any { t ->
        t.name.contains("Release") &&
            (t.name.startsWith("assemble") || t.name.startsWith("bundle") ||
                t.name.startsWith("package"))
    }
    if (!releaseTask) return@whenReady
    val problems = mutableListOf<String>()
    if (dartDefines["AO_BACKEND"] != "supabase") {
        problems += "Release builds are cloud-only: build with " +
            "--dart-define-from-file=dart_define.prod.json (AO_BACKEND=supabase, " +
            "the hosted https URL and its publishable key). Local mode — demo data " +
            "and default PINs — is for development builds only."
    }
    if (!hasReleaseKey) {
        problems += "Release signing is not configured. Create android/key.properties " +
            "(storeFile, storePassword, keyAlias, keyPassword) for the release " +
            "keystore — see docs/RELEASE.md §4. Refusing to build a release " +
            "signed with the debug key."
    }
    if (problems.isNotEmpty()) throw GradleException(problems.joinToString("\n"))
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Backports java.time etc. for flutter_local_notifications on older Android.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
