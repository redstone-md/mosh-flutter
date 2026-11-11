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
    private val local by lazy { lane() }
    private val remote by lazy { lane() }

    /** Held for the process: a producer nobody holds releases its surface. */
    private val producers = mutableListOf<TextureRegistry.SurfaceProducer>()

    init {
        MethodChannel(messenger, "mosh/call-video").setMethodCallHandler { method, result ->
            if (method.method == "textures") {
                result.success(mapOf("local" to local, "remote" to remote))
            } else {
                result.notImplemented()
            }
        }
    }

    /**
     * One lane as `[texture id, export address]`. Rust keeps the address. The
     * producer is never resized and Flutter does not reset it in the
     * background, so its surface stays the one Rust holds; each frame sets
     * the size of its own buffer. A lane Rust cannot take gives its producer
     * back and is made again on the next request.
     */
    private fun lane(): List<Long> {
        val producer = registry.createSurfaceProducer(TextureRegistry.SurfaceLifecycle.manual)
        try {
            val address = export(producer.surface)
            check(address != 0L) { "Call video texture unavailable" }
            producers += producer
            return listOf(producer.id(), address)
        } catch (error: RuntimeException) {
            producer.release()
            throw error
        }
    }

    companion object {
        @JvmStatic private external fun export(surface: Surface): Long
    }
}
