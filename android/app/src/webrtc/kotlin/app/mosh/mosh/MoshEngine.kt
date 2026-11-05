package app.mosh.mosh

import android.content.Context
import livekit.org.webrtc.ContextUtils

/**
 * The engine links libwebrtc statically. Loading it from Java lets libwebrtc
 * capture this class loader (its JNI_OnLoad); mosh-core later opens the same
 * library. Its audio module reads the application context from ContextUtils.
 */
internal object MoshEngine {
    fun initialize(context: Context) {
        System.loadLibrary("mosh_native_media")
        ContextUtils.initialize(context.applicationContext)
    }
}
