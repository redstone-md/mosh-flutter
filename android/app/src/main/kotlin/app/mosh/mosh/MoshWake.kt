package app.mosh.mosh

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * This phone's side of its wake registration for Dart
 * (lib/src/platform/android_wake.dart): the build's push token, and the
 * registration and preview keys the push service reads while Mosh is
 * closed. A build without a push service ([MoshPush.wakeable] false) has no
 * token, and Dart does not register it.
 */
internal class MoshWake(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "app.mosh.mosh/wake")
    private val vault = MoshWakeVault(context)
    private val main = Handler(Looper.getMainLooper())
    private val storage = Executors.newSingleThreadExecutor()

    init {
        channel.setMethodCallHandler(::dispatch)
    }

    /** The push address Dart last took; Firebase reports it again on every registration. */
    @Volatile private var handed: String? = null

    /** The push service reports [installation]: Dart registers it when it is new. */
    fun tokensChanged(installation: String) {
        if (installation == handed) return
        main.post { channel.invokeMethod("tokens", null) }
    }

    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "wakeable" -> result.success(MoshPush.wakeable)
            "tokens" -> MoshPush.token { token ->
                handed = token
                main.post { result.success(token?.let { mapOf("fcm" to it) }) }
            }
            "loadRegistration" -> stored(result) { vault.read(REGISTRATION) }
            "saveRegistration" -> stored(result) { vault.write(REGISTRATION, call.arguments as String) }
            "savePreviews" -> stored(result) { vault.write(PREVIEWS, call.arguments as String) }
            else -> result.notImplemented()
        }
    }

    /** Keystore and file work off the main thread; a failure reaches Dart without its detail. */
    private fun stored(result: MethodChannel.Result, work: () -> Any?) {
        storage.execute {
            val outcome = runCatching(work)
            main.post {
                outcome.fold(result::success) { result.error("WAKE_STORAGE", "Wake storage unavailable", null) }
            }
        }
    }

    companion object {
        private const val REGISTRATION = "registration"
        private const val PREVIEWS = "previews"

        /** The chats a preview may come from, as Dart last saved them; null when none are. */
        fun previews(context: Context): String? = MoshWakeVault(context).read(PREVIEWS)
    }
}
