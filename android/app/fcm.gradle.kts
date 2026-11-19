// Firebase Cloud Messaging for the Google Play and GitHub builds (ADR 0055),
// applied by build.gradle.kts with -PmoshFcm=true. F-Droid's recipe removes
// this file and src/fcm, so its build has no Google code or dependency.
//
// Firebase starts from string resources that Google's google-services plugin
// would generate from google-services.json; the four it needs are read here
// instead, which keeps the plugin out of the build. -PmoshFcmConfig names the
// file, by default google-services.json next to this one.
import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.variant.ApplicationAndroidComponentsExtension
import groovy.json.JsonSlurper

val firebaseConfig = file(providers.gradleProperty("moshFcmConfig").orNull ?: "google-services.json")
check(firebaseConfig.isFile) { "The FCM build needs Firebase's google-services.json at $firebaseConfig" }

val firebase = JsonSlurper().parse(firebaseConfig) as Map<*, *>
val firebaseProject = firebase["project_info"] as Map<*, *>
val firebaseClient = (firebase["client"] as List<*>).map { it as Map<*, *> }.single { client ->
    val info = client["client_info"] as Map<*, *>
    (info["android_client_info"] as Map<*, *>)["package_name"] == "app.mosh.mosh"
}

extensions.configure<ApplicationExtension> {
    buildFeatures.resValues = true
    defaultConfig {
        resValue("string", "google_app_id", (firebaseClient["client_info"] as Map<*, *>)["mobilesdk_app_id"] as String)
        resValue("string", "google_api_key", ((firebaseClient["api_key"] as List<*>).first() as Map<*, *>)["current_key"] as String)
        resValue("string", "gcm_defaultSenderId", firebaseProject["project_number"] as String)
        resValue("string", "project_id", firebaseProject["project_id"] as String)
    }
    sourceSets.getByName("test").kotlin.directories.add("src/fcmTest/kotlin")
}

extensions.configure<ApplicationAndroidComponentsExtension> {
    onVariants { variant -> variant.sources.manifests.addStaticManifestFile("src/fcm/AndroidManifest.xml") }
}

dependencies {
    "implementation"("com.google.firebase:firebase-messaging:26.0.2")
    // Ed25519 for group previews' signatures, which Android has only from API 33.
    "implementation"("com.google.crypto.tink:tink-android:1.24.0")
    "testImplementation"("junit:junit:4.13.2")
    // The real org.json: Android's is a stub in local unit tests.
    "testImplementation"("org.json:json:20260814")
}
