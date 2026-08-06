import java.io.File
import java.util.Properties
import org.gradle.api.tasks.Exec
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

private fun findTool(name: String): File {
    val executableName = if (System.getProperty("os.name").startsWith("Windows", ignoreCase = true)) "$name.exe" else name
    return System.getenv("PATH").orEmpty()
        .split(File.pathSeparator)
        .asSequence()
        .map { File(it, executableName) }
        .firstOrNull(File::isFile)
        ?: File("__missing_moss_$name")
}

private fun resolveNdkRoot(version: String, localPropertiesFile: File): File {
    val configuredRoot = System.getenv("ANDROID_NDK_HOME")
        ?: System.getenv("ANDROID_NDK_ROOT")
    val localProperties = Properties()
    localPropertiesFile.takeIf(File::isFile)?.inputStream()?.use(localProperties::load)
    val sdkRoot = localProperties.getProperty("sdk.dir")?.let(::File)
    val installedNdk = sdkRoot?.resolve("ndk")?.resolve(version)
    return configuredRoot?.let(::File)
        ?: installedNdk
        ?: File("__missing_moss_ndk__")
}

android {
    namespace = "app.mosh.mosh"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (v22.x) requires core library
        // desugaring on Android (java.time APIs etc.). See ADR/slice-3
        // device-pass: enabling this is what lets assembleDebug produce an
        // installable APK on AGP 9.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.mosh.mosh"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // AAudio (cpal 0.18.1's Android backend, deps `ndk = { features =
        // ["audio", "api-level-26"] }`) links -laaudio, which only ships in
        // the NDK sysroot at api 26+ (libaaudio.so is absent from /24/).
        // Flutter's default minSdk (24 for 3.44) is too low for the link, so
        // hardcode 26 here. This also flows through Cargokit (plugin.gradle
        // reads defaultConfig.minSdkVersion and android_environment.dart
        // sets --target=aarch64-linux-android26), so the cargo cross-compile
        // resolves libaaudio.so from the sysroot /26/ dir too. Single edit,
        // two effects. Do not revert to flutter.minSdkVersion.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Slice-3 device-pass: restrict to arm64-v8a for now. The provisioned
        // libopus.a (see rust_builder/cargokit/gradle/plugin.gradle) is
        // aarch64-only, so Cargokit can only build libmosh_core.so for arm64.
        // Expand to all ABIs once per-ABI opus artifacts exist.
        ndk { abiFilters += "arm64-v8a" }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

val repositoryRoot = rootProject.projectDir.parentFile
val mossCheckout = repositoryRoot.resolve("moss")
val mossPreparationScript = repositoryRoot.resolve("scripts/moss-prepare-android.mjs")
val mossOutput = project.file("src/main/jniLibs/arm64-v8a/libmoss.so")
val mossNdkVersion = flutter.ndkVersion
val mossNdkRoot = providers.provider {
    resolveNdkRoot(mossNdkVersion, rootProject.file("local.properties"))
}
val mossNode = providers.provider { findTool("node") }
val mossGo = providers.provider { findTool("go") }

val mossPreparation = tasks.register<Exec>("prepareMossAndroid") {
    inputs.file(mossPreparationScript).withPathSensitivity(PathSensitivity.NONE)
    inputs.files(mossNode, mossGo)
        .withPathSensitivity(PathSensitivity.NONE)
        .optional()
    inputs.property("androidNdkRoot", mossNdkRoot.map { it.absolutePath })
    inputs.files(fileTree(mossCheckout) {
        include("**/*.go", "**/*.mmdb.gz", "go.mod", "go.sum")
        exclude(".git/**", "**/build/**", "**/*_test.go")
    }).withPathSensitivity(PathSensitivity.RELATIVE)
    outputs.file(mossOutput)

    workingDir(repositoryRoot)
    doFirst {
        fun requireFile(file: File, description: String) {
            check(file.isFile) { "$description not found at ${file.absolutePath}" }
        }

        val node = mossNode.get().takeIf(File::isFile)
            ?: error("Moss Android preparation requires Node.js on PATH; install it and retry the Android build")
        val go = mossGo.get().takeIf(File::isFile)
            ?: error("Moss Android preparation requires Go on PATH; install it and retry the Android build")
        val ndk = mossNdkRoot.get().takeIf(File::isDirectory)
            ?: error("Moss Android preparation requires Android NDK $mossNdkVersion; set ANDROID_NDK_HOME or install it under sdk.dir from local.properties")
        requireFile(mossPreparationScript, "Moss Android preparation script")

        environment("ANDROID_NDK_HOME", ndk.absolutePath)
        environment("PATH", listOf(go.parentFile.absolutePath, System.getenv("PATH")).joinToString(File.pathSeparator))
        commandLine(node.absolutePath, mossPreparationScript.absolutePath)
    }
}

tasks.named("preBuild") {
    dependsOn(mossPreparation)
}
