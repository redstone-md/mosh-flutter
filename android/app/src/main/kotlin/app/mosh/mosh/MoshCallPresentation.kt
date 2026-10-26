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

/** Engine-owned call configuration; only the attached Activity owns the PiP view. */
internal class MoshCallPresentation(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "app.mosh/call-presentation")
    private var activity: MainActivity? = null
    private val supported get() = activity?.packageManager
        ?.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE) == true
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
            configureWindow()
            result.success(null)
        }
    }

    fun attach(activity: MainActivity) {
        unshield()
        this.activity = activity
        closing = false
        enteredCall = call.takeIf { activity.isInPictureInPictureMode }
        configureWindow()
        if (activity.isInPictureInPictureMode) preparing()
    }

    fun detach(activity: MainActivity) {
        if (this.activity !== activity) return
        unshield()
        this.activity = null
        resumed = false
    }

    private fun configureWindow() {
        val activity = activity ?: return
        if (!supported) return
        try {
            activity.setPictureInPictureParams(params())
            if (call == null && activity.isInPictureInPictureMode) activity.finish()
        } catch (_: RuntimeException) {
            // A finishing Activity cannot update its PiP parameters.
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
        val activity = activity ?: return
        if (!supported || !video || closing) return
        // Hide chats before the Activity is shrunk, including Android 12 auto-enter.
        preparing()
        if (Build.VERSION.SDK_INT < 31) {
            val entered = try { activity.enterPictureInPictureMode(params()) }
                catch (_: RuntimeException) { false }
            if (!entered) { unshield(); mode(false) }
        }
    }

    fun preparing() {
        if (!supported || !video || closing) return
        shield()
        mode(true)
    }

    fun changed(pip: Boolean) {
        if (pip) {
            enteredCall = call
            shield()
            mode(true)
        } else if (resumed) mode(false)
    }

    fun resumed() {
        val activity = activity ?: return
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
        val activity = activity ?: return
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
        val activity = activity ?: return
        if (shield != null) return
        shield = View(activity).apply { setBackgroundColor(Color.BLACK) }
        activity.addContentView(shield, ViewGroup.LayoutParams(-1, -1))
    }

    private fun unshield() {
        shield?.let { (it.parent as? ViewGroup)?.removeView(it) }
        shield = null
    }
}
