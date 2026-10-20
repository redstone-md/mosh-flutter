package app.mosh.mosh

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.graphics.Color
import android.util.Rational
import android.view.View
import android.view.ViewGroup
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** System PiP uses the same Flutter renderer; it never starts a second call. */
internal class MoshCallPresentation(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "app.mosh/call-presentation")
    private val supported = activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    private var call: String? = null
    private var video = false
    private var enteredCall: String? = null
    private var closing = false
    private var resumed = false
    private var shield: View? = null

    init {
        channel.setMethodCallHandler { method, result ->
            if (method.method == "ready") {
                if (method.argument<String>("call") == call) unshield()
                result.success(null)
                return@setMethodCallHandler
            }
            if (method.method != "configure") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            call = method.argument<String>("call")
            video = method.argument<Boolean>("video") == true && call != null
            if (supported) {
                try {
                    activity.setPictureInPictureParams(params())
                    if (call == null && activity.isInPictureInPictureMode) activity.finish()
                } catch (_: RuntimeException) {
                    // A finishing Activity cannot update its PiP parameters.
                }
            }
            result.success(null)
        }
    }

    private fun params(): PictureInPictureParams = PictureInPictureParams.Builder().apply {
        setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= 31) {
            setAutoEnterEnabled(video)
            setSeamlessResizeEnabled(false)
        }
    }.build()

    fun leaving() {
        if (!supported || !video || closing) return
        // Hide chats before the Activity is shrunk, including Android 12 auto-enter.
        shield()
        mode(true)
        if (Build.VERSION.SDK_INT < 31) {
            val entered = try { activity.enterPictureInPictureMode(params()) }
                catch (_: RuntimeException) { false }
            if (!entered) { unshield(); mode(false) }
        }
    }

    fun changed(pip: Boolean) {
        if (pip) {
            enteredCall = call
            shield()
            mode(true)
        } else if (resumed) mode(false)
    }

    fun resumed() {
        resumed = true
        if (!activity.isInPictureInPictureMode) {
            enteredCall = null
            closing = false
            unshield()
            mode(false)
        }
    }

    fun paused() { resumed = false }

    fun stopped() {
        val ended = enteredCall ?: return
        if (closing || activity.isChangingConfigurations) return
        closing = true
        // Closing PiP must not leave a hidden microphone/camera owner running.
        channel.invokeMethod("closed", mapOf("call" to ended))
    }

    private fun mode(pip: Boolean) {
        channel.invokeMethod("mode", mapOf("call" to call, "pip" to pip))
    }

    // Flutter's mode callback is asynchronous. Cover the old chat until a frame
    // containing only video has actually painted; never shrink a chat into PiP.
    private fun shield() {
        if (shield != null) return
        shield = View(activity).apply { setBackgroundColor(Color.BLACK) }
        activity.addContentView(shield, ViewGroup.LayoutParams(-1, -1))
    }

    private fun unshield() {
        shield?.let { (it.parent as? ViewGroup)?.removeView(it) }
        shield = null
    }

    fun dispose() { channel.setMethodCallHandler(null); unshield() }
}
