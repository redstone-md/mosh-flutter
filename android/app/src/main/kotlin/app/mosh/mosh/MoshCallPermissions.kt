package app.mosh.mosh

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Activity permission UI only; no camera or call lifetime is owned here. */
internal class MoshCallPermissions(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "app.mosh/call_permissions")
    private val pending = mutableListOf<MethodChannel.Result>()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "camera" -> request(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun request(result: MethodChannel.Result) {
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pending.add(result)
        if (pending.size == 1) activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST)
    }

    fun complete(request: Int, grants: IntArray) {
        if (request != REQUEST) return
        val allowed = grants.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pending.toList().also { pending.clear() }.forEach { it.success(allowed) }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pending.toList().also { pending.clear() }.forEach { it.success(false) }
    }

    companion object { private const val REQUEST = 7021 }
}
