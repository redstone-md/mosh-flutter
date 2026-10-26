package app.mosh.mosh

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal

/** Strong biometric/credential UI only. A detached Activity can never grant access. */
internal class MoshChatAuthentication(private val context: Context) {
    private var activity: MainActivity? = null
    private var pending: Attempt? = null
    private var resumed = false
    val showing get() = pending != null
    val credentialShowing get() = pending?.credential == true

    private class Attempt(val activity: MainActivity, val complete: (String) -> Unit) {
        val cancellation = CancellationSignal()
        var credential = false
        var succeeded = false
    }

    fun attach(activity: MainActivity) {
        if (this.activity !== activity) cancel()
        this.activity = activity
    }

    fun detach(activity: MainActivity) {
        if (this.activity !== activity) return
        cancel()
        this.activity = null
        resumed = false
    }

    fun resumed() {
        resumed = true
        pending?.takeIf { it.succeeded }?.let { finish(it, "authenticated") }
    }

    fun paused() { resumed = false }

    fun authenticate(reason: String, complete: (String) -> Unit) {
        val activity = activity
        if (activity == null || !resumed || pending != null) { complete("canceled"); return }
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        if (!keyguard.isDeviceSecure) { complete("unavailable"); return }
        val attempt = Attempt(activity, complete)
        pending = attempt
        try {
            if (Build.VERSION.SDK_INT >= 30) biometric(attempt, reason)
            else credential(attempt, reason)
        } catch (_: Exception) { finish(attempt, "unavailable") }
    }

    @android.annotation.TargetApi(30)
    private fun biometric(attempt: Attempt, reason: String) {
        val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL
        val manager = context.getSystemService(BiometricManager::class.java)
        if (manager.canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
            finish(attempt, "unavailable")
            return
        }
        BiometricPrompt.Builder(attempt.activity).setTitle(reason)
            .setAllowedAuthenticators(authenticators).build()
            .authenticate(attempt.cancellation, attempt.activity.mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        if (pending !== attempt || activity !== attempt.activity) return
                        attempt.succeeded = true
                        if (resumed) finish(attempt, "authenticated")
                    }
                    override fun onAuthenticationError(code: Int, message: CharSequence) {
                        val canceled = code == BiometricPrompt.BIOMETRIC_ERROR_CANCELED ||
                            code == BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED
                        finish(attempt, if (canceled) "canceled" else "unavailable")
                    }
                })
    }

    @Suppress("DEPRECATION")
    private fun credential(attempt: Attempt, reason: String) {
        val intent = context.getSystemService(KeyguardManager::class.java)
            .createConfirmDeviceCredentialIntent(reason, null)
        if (intent == null) { finish(attempt, "unavailable"); return }
        attempt.credential = true
        attempt.activity.startActivityForResult(intent, REQUEST)
    }

    fun result(request: Int, code: Int) {
        if (request != REQUEST) return
        val attempt = pending ?: return
        if (!attempt.credential) return
        if (code != Activity.RESULT_OK) { finish(attempt, "canceled"); return }
        attempt.succeeded = true
        if (resumed) finish(attempt, "authenticated")
    }

    fun cancel() {
        val attempt = pending ?: return
        finish(attempt, "canceled")
        attempt.cancellation.cancel()
    }

    private fun finish(attempt: Attempt, result: String) {
        if (pending !== attempt || activity !== attempt.activity) return
        pending = null
        attempt.complete(result)
    }

    companion object { private const val REQUEST = 7022 }
}
