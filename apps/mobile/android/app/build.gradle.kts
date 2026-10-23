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
        // API 26 (Android 8.0) floor, kept from when sentry_flutter required it.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One flavor per environment (lib/core/config/app_config.dart). Separate
    // application ids keep each environment's device database and sign-in apart
    // and let all three be installed side by side; prod keeps the original id.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appName"] = "ARQ DEV"
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            manifestPlaceholders["appName"] = "ARQ QA"
        }
        create("prod") {
            dimension = "env"
            manifestPlaceholders["appName"] = "ARQ"
        }
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
// (comma-separated, each base64 "KEY=value"). Only AO_BACKEND and
// AO_ENVIRONMENT are read here.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.mapNotNull { runCatching { String(Base64.getDecoder().decode(it)) }.getOrNull() }
        ?.mapNotNull { d -> d.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
        ?.toMap()
        ?: emptyMap()

// The environment each flavor's builds must carry (AO_ENVIRONMENT), and its
// define file. Mirrors AppConfig.environmentForFlavor.
val environmentForFlavor = mapOf(
    "dev" to "development",
    "staging" to "staging",
    "prod" to "production",
)
val defineFileForFlavor = mapOf(
    "dev" to "dart_define.local.json",
    "staging" to "dart_define.staging.json",
    "prod" to "dart_define.prod.json",
)

// Profile and release APK/AAB builds must match their flavor's environment;
// dev never builds a release; staging/prod are cloud-only; a release carries
// the release key. Fail fast, before anything is built, and say what to do.
// (Debug builds are untouched; the app itself checks every build at start.)
gradle.taskGraph.whenReady {
    val builds = allTasks.mapNotNull { t ->
        Regex("^(assemble|bundle|package)(Dev|Staging|Prod)(Release|Profile)$")
            .find(t.name)
            ?.let { it.groupValues[2].lowercase() to it.groupValues[3] }
    }.toSet()
    if (builds.isEmpty()) return@whenReady
    val problems = linkedSetOf<String>()
    val environment = dartDefines["AO_ENVIRONMENT"] ?: "development"
    for ((flavor, mode) in builds) {
        val expected = environmentForFlavor.getValue(flavor)
        val defineFile = defineFileForFlavor.getValue(flavor)
        if (flavor == "dev" && mode == "Release") {
            problems += "The dev flavor never builds a release: local mode (demo " +
                "data, default PINs) and the local stack are for development only. " +
                "Build releases with --flavor staging or --flavor prod and their " +
                "define file."
            continue
        }
        if (environment != expected) {
            problems += "The $flavor flavor must be built for AO_ENVIRONMENT=$expected " +
                "(the dart-defines say \"$environment\"): build with " +
                "--dart-define-from-file=$defineFile."
        }
        if (flavor != "dev" && dartDefines["AO_BACKEND"] != "supabase") {
            problems += "The $flavor flavor is cloud-only: build with " +
                "--dart-define-from-file=$defineFile (AO_BACKEND=supabase, the " +
                "project's https URL and its publishable key)."
        }
        if (mode == "Release" && !hasReleaseKey) {
            problems += "Release signing is not configured. Create android/key.properties " +
                "(storeFile, storePassword, keyAlias, keyPassword) for the release " +
                "keystore — see docs/RELEASE.md §4. Refusing to build a release " +
                "signed with the debug key."
        }
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
