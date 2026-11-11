package app.mosh.mosh

import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * The call's two video textures. Flutter draws them and Rust writes every
 * frame into their surfaces, so no pixel passes through Dart or this class.
 */
internal class MoshCallVideo(messenger: BinaryMessenger, private val registry: TextureRegistry) {
    private val textures by lazy { mapOf("local" to lane(), "remote" to lane()) }

    init {
        MethodChannel(messenger, "mosh/call-video").setMethodCallHandler { method, result ->
            if (method.method == "textures") result.success(textures) else result.notImplemented()
        }
    }

    /**
     * One lane as `[texture id, export address]`. Never released: Rust keeps
     * the address. The producer is never resized, so its surface stays the
     * one Rust holds; each frame sets the size of its own buffer.
     */
    private fun lane(): List<Long> {
        val producer = registry.createSurfaceProducer()
        val address = export(producer.surface)
        check(address != 0L) { "Call video texture unavailable" }
        return listOf(producer.id(), address)
    }

    companion object {
        @JvmStatic private external fun export(surface: Surface): Long
    }
}
