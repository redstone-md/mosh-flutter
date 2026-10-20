package app.mosh.mosh

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import java.nio.ByteBuffer
import org.json.JSONArray
import org.json.JSONObject
import org.webrtc.Camera2Enumerator
import org.webrtc.Camera1Enumerator
import org.webrtc.CameraEnumerator
import org.webrtc.CameraVideoCapturer
import org.webrtc.CapturerObserver
import org.webrtc.EglBase
import org.webrtc.SurfaceTextureHelper
import org.webrtc.VideoFrame
import org.webrtc.YuvHelper

/** Camera work never blocks the native call owner or the Flutter UI thread. */
internal class MoshCallCamera(private val context: Context) {
    private val handler = Handler(HandlerThread("MoshCameraOwner").apply { start() }.looper)
    private var capturer: CameraVideoCapturer? = null
    private var texture: SurfaceTextureHelper? = null
    private var egl: EglBase? = null

    private fun enumerator(): CameraEnumerator = if (Camera2Enumerator.isSupported(context)) {
        Camera2Enumerator(context)
    } else Camera1Enumerator(true)

    fun devices(): JSONObject {
        val enumerator = enumerator()
        val cameras = JSONArray()
        for (id in enumerator.deviceNames) {
            val name = when {
                enumerator.isFrontFacing(id) -> "Front camera"
                enumerator.isBackFacing(id) -> "Back camera"
                else -> "Camera"
            }
            cameras.put(JSONObject().put("id", id).put("name", "$name ($id)")
                .put("stable", true))
        }
        return JSONObject().put("cameras", cameras)
    }

    fun start(value: JSONObject) {
        val generation = value.getLong("generation")
        val requested = value.optString("id").takeUnless { it.isBlank() || it == "null" }
        handler.post {
            release()
            try {
                open(requested, generation)
            } catch (_: Exception) {
                cameraFailed(generation)
                release()
            }
        }
    }

    private fun open(requested: String?, generation: Long) {
        val enumerator = enumerator()
        val id = requested?.also { check(it in enumerator.deviceNames) }
            ?: enumerator.deviceNames.firstOrNull { enumerator.isFrontFacing(it) }
            ?: enumerator.deviceNames.firstOrNull() ?: error("No camera")
        val events = object : CameraVideoCapturer.CameraEventsHandler {
            override fun onCameraError(error: String) = cameraFailed(generation)
            override fun onCameraDisconnected() = cameraFailed(generation)
            override fun onCameraFreezed(error: String) = cameraFailed(generation)
            override fun onCameraOpening(name: String) { }
            override fun onFirstFrameAvailable() { }
            override fun onCameraClosed() { }
        }
        egl = EglBase.create()
        texture = SurfaceTextureHelper.create("MoshCameraFrames", egl!!.eglBaseContext)
            ?: error("Camera texture unavailable")
        capturer = enumerator.createCapturer(id, events) ?: error("Camera unavailable")
        capturer!!.initialize(texture, context, observer(generation))
        // WebRTC selects a supported native format and FPS range for this request.
        capturer!!.startCapture(640, 480, 30)
    }

    private fun observer(generation: Long) = object : CapturerObserver {
        private var packed: ByteBuffer? = null
        override fun onCapturerStarted(success: Boolean) {
            if (!success) cameraFailed(generation)
        }
        override fun onCapturerStopped() { }
        override fun onFrameCaptured(frame: VideoFrame) {
            val planar = frame.buffer.toI420() ?: return
            try {
                val w = planar.width
                val h = planar.height
                if (w <= 0 || h <= 0 || w > 1920 || h > 1920 || w * h > 1920 * 1080) return
                val size = w * h + 2 * ((w + 1) / 2) * ((h + 1) / 2)
                val buffer = packed?.takeIf { it.capacity() == size }
                    ?: ByteBuffer.allocateDirect(size).also { packed = it }
                buffer.clear()
                YuvHelper.I420Rotate(planar.dataY, planar.strideY, planar.dataU,
                    planar.strideU, planar.dataV, planar.strideV, buffer, w, h, frame.rotation)
                val sideways = frame.rotation == 90 || frame.rotation == 270
                cameraFrame(generation, if (sideways) h else w, if (sideways) w else h, buffer)
            } catch (_: Exception) {
                cameraFailed(generation)
            } finally {
                planar.release()
            }
        }
    }

    fun stop() { handler.post { release() } }

    private fun release() {
        val oldCapturer = capturer
        val oldTexture = texture
        val oldEgl = egl
        capturer = null
        texture = null
        egl = null
        try {
            oldCapturer?.stopCapture()
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        } catch (_: Exception) {
            // Device removal can fail stopCapture; dispose the remaining owners.
        } finally {
            runCatching { oldCapturer?.dispose() }
            runCatching { oldTexture?.dispose() }
            runCatching { oldEgl?.release() }
        }
    }

    companion object {
        @JvmStatic private external fun cameraFrame(generation: Long, width: Int,
            height: Int, pixels: ByteBuffer)
        @JvmStatic private external fun cameraFailed(generation: Long)
    }
}
