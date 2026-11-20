package app.mosh.mosh

import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * How long a call wake push keeps Moss connected (ADR 0055): long enough for
 * the caller's 30 s ring, after which [ended] lets the waiting choice decide
 * again. A call that rings keeps Mosh connected by itself.
 */
internal class MoshWokenWindow(ended: () -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private val end = Runnable(ended)
    private var until = 0L

    val open: Boolean get() = SystemClock.elapsedRealtime() < until

    fun start() {
        until = SystemClock.elapsedRealtime() + LENGTH_MS
        main.removeCallbacks(end)
        main.postDelayed(end, LENGTH_MS)
    }

    private companion object {
        const val LENGTH_MS = 45_000L
    }
}
