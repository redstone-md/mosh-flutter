package app.mosh.mosh

import android.content.Context
import org.webrtc.PeerConnectionFactory

/** RingRTC's libwebrtc lives in its own library, loaded and initialized here. */
internal object MoshEngine {
    fun initialize(context: Context) {
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context)
                .setNativeLibraryName("ringrtc_rffi")
                .setEnableInternalTracer(false)
                .createInitializationOptions()
        )
    }
}
