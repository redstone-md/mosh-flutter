package app.mosh.mosh

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream

/**
 * One frame of a video file as a JPEG, for the previews of an attachment
 * being sent. The platform's decoder takes it, off the main thread.
 */
internal class MoshVideoFrame(messenger: BinaryMessenger) {
    init {
        val background = messenger.makeBackgroundTaskQueue()
        MethodChannel(messenger, "mosh/video-frame", StandardMethodCodec.INSTANCE, background)
            .setMethodCallHandler { method, result ->
                if (method.method != "take") return@setMethodCallHandler result.notImplemented()
                try {
                    result.success(take(method.arguments as String))
                } catch (error: RuntimeException) {
                    // The retriever refuses a file it has no decoder for.
                    result.error("video-frame", error.message, null)
                } catch (error: OutOfMemoryError) {
                    // Android 8.0 decodes the frame at the video's full size.
                    result.error("video-frame", "The frame does not fit in memory", null)
                }
            }
    }

    /**
     * The key frame nearest a tenth into the video, a second in at most; null
     * when the video has none. Dart scales it to the previews' sizes; here
     * it is only made small to hand over, which Android 8.0 cannot do.
     */
    private fun take(path: String): ByteArray? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val length = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val at = minOf((length?.toLongOrNull() ?: 0) / 10, 1_000) * 1_000
            val nearest = MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            val frame = if (Build.VERSION.SDK_INT >= 27) {
                retriever.getScaledFrameAtTime(at, nearest, EDGE, EDGE)
            } else {
                retriever.getFrameAtTime(at, nearest)
            } ?: return null
            val jpeg = ByteArrayOutputStream()
            frame.compress(Bitmap.CompressFormat.JPEG, 90, jpeg)
            frame.recycle()
            return jpeg.toByteArray()
        } finally {
            retriever.release()
        }
    }

    private companion object {
        /** Twice the preview's longest edge. */
        const val EDGE = 640
    }
}
