package app.mosh.mosh

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Capture waits for actual typed foreground-service promotion, not a queued start. */
internal class MoshWaitingMedia(private val context: Context, private val visible: () -> Boolean,
    private val start: () -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var microphone = false
    private var camera = false
    private val timeout = Runnable { complete(false) }

    fun set(value: Map<*, *>, result: MethodChannel.Result) {
        if (pending != null) { result.success(false); return }
        microphone = value["microphone"] as? Boolean ?: error("Missing microphone type")
        camera = value["camera"] as? Boolean ?: error("Missing camera type")
        if (!authorized()) { result.success(false); return }
        pending = result
        if (MoshWaitingService.running || !microphone && !camera) apply()
        else { handler.postDelayed(timeout, 3_000); start() }
    }

    fun serviceChanged() { if (MoshWaitingService.running) apply() }
    fun paused() { if (pending != null) complete(false) }

    private fun authorized(): Boolean {
        if (!microphone && !camera) return true
        if (!visible()) return false
        return (!microphone || granted(Manifest.permission.RECORD_AUDIO)) && (!camera || granted(Manifest.permission.CAMERA))
    }

    private fun granted(permission: String) = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun apply() {
        if (pending == null) return
        complete(authorized() && MoshWaitingService.mediaTypes(microphone, camera))
    }

    private fun complete(value: Boolean) {
        handler.removeCallbacks(timeout)
        val result = pending
        pending = null
        result?.success(value)
    }
}
