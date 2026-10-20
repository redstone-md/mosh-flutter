package app.mosh.mosh

import android.content.Context
import org.json.JSONObject
import org.webrtc.PeerConnectionFactory

/** Application-scoped platform resources. Call ownership stays in Rust. */
internal object MoshMedia {
    private lateinit var audio: MoshCallAudio
    private lateinit var camera: MoshCallCamera
    private var initialized = false

    @Synchronized
    fun initialize(context: Context) {
        if (initialized) return
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context)
                .setNativeLibraryName("ringrtc_rffi")
                .setEnableInternalTracer(false)
                .createInitializationOptions()
        )
        audio = MoshCallAudio(context)
        camera = MoshCallCamera(context)
        register()
        initialized = true
    }

    @JvmStatic
    private external fun register()

    @JvmStatic
    fun command(json: String): String = try {
        val value = JSONObject(json)
        when (value.getString("action")) {
            "devices" -> audio.devices()
            "select" -> audio.select(value)
            "audioStop" -> { audio.stop(); JSONObject() }
            "cameras" -> camera.devices()
            "cameraStart" -> { camera.start(value); JSONObject() }
            "cameraStop" -> { camera.stop(); JSONObject() }
            else -> error("Unknown Android media command")
        }.toString()
    } catch (error: Exception) {
        JSONObject().put("error", error.javaClass.simpleName).toString()
    }
}
