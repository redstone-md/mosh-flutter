package app.mosh.mosh

import android.content.Context

/** Supplies the process-wide application context to CPAL before Dart starts. */
internal object MoshNative {
    init {
        System.loadLibrary("mosh_core")
    }

    @JvmStatic
    external fun initialize(application: Context)

    @JvmStatic
    external fun notifyNetworkChanged(): Int
}
