package app.mosh.mosh

import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.messaging.FirebaseMessaging

/**
 * The push service this build is woken through: Firebase Cloud Messaging
 * (ADR 0055), which reaches this phone by its Firebase installation id once
 * it is registered. The id is null on a phone without Google Play services,
 * or until registration succeeds; [MoshFcmService] says when it changes.
 */
internal object MoshPush {
    val platform: String? = "fcm"

    fun token(done: (String?) -> Unit) {
        try {
            FirebaseMessaging.getInstance().register().addOnCompleteListener { registered ->
                if (!registered.isSuccessful) return@addOnCompleteListener done(null)
                FirebaseInstallations.getInstance().id.addOnCompleteListener { id ->
                    done(if (id.isSuccessful) id.result else null)
                }
            }
        } catch (_: IllegalStateException) {
            // Firebase did not start: the build has no project settings.
            done(null)
        }
    }
}
