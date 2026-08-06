import com.android.build.api.dsl.LibraryExtension
import com.android.build.api.variant.LibraryAndroidComponentsExtension
import org.gradle.api.Project
import org.gradle.kotlin.dsl.configure
import javax.xml.parsers.DocumentBuilderFactory

private val validJavaPackage = Regex("[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*")
private val androidLibraryCompileSdkFloor = 34

private fun String.asJavaPackage(): String =
    split('.')
        .map { segment ->
            val cleaned = segment.replace(Regex("[^A-Za-z0-9_]"), "_")
            when {
                cleaned.isEmpty() -> "_"
                cleaned.first().isDigit() -> "_$cleaned"
                else -> cleaned
            }
        }
        .joinToString(".")

private fun Project.androidLibraryNamespace(): String {
    val manifest = file("src/main/AndroidManifest.xml")
    val manifestPackage = if (manifest.isFile) {
        runCatching {
            DocumentBuilderFactory.newInstance()
                .newDocumentBuilder()
                .parse(manifest)
                .documentElement
                .getAttribute("package")
                .trim()
        }.getOrNull()
    } else {
        null
    }

    if (!manifestPackage.isNullOrEmpty() && validJavaPackage.matches(manifestPackage)) {
        return manifestPackage
    }

    val groupPackage = group.toString()
        .takeUnless { it.isBlank() || it == "unspecified" }
        ?.asJavaPackage()
        ?: "com.mosh.compat"
    return "$groupPackage.${name.asJavaPackage()}"
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<LibraryExtension> {
            if (namespace == null) {
                namespace = project.androidLibraryNamespace()
            }
        }
        extensions.configure<LibraryAndroidComponentsExtension> {
            finalizeDsl {
                if (it.compileSdkPreview == null && (it.compileSdk ?: 0) < androidLibraryCompileSdkFloor) {
                    it.compileSdk = androidLibraryCompileSdkFloor
                }
            }
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
