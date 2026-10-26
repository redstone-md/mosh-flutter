package app.mosh.mosh

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import java.util.concurrent.Executors

/** One default-network observer; the existing Moss owner coalesces/reconciles hints. */
internal class MoshWaitingNetwork(context: Context, private val unavailable: () -> Unit) {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val power = context.getSystemService(PowerManager::class.java)
    private val worker = Executors.newSingleThreadExecutor { task -> Thread(task, "mosh-network-hint").apply { isDaemon = true } }
    private var observing = false
    private var running = false
    private var dirty = false
    private val deliver = Runnable { drain() }
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = changed()
        override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) = changed()
        override fun onLost(network: Network) = changed()
    }

    fun observe(enabled: Boolean) {
        if (enabled == observing) return
        observing = enabled
        try {
            if (enabled) manager.registerDefaultNetworkCallback(callback, handler)
            else manager.unregisterNetworkCallback(callback)
        } catch (_: RuntimeException) { observing = false; unavailable() }
        if (!observing) { dirty = false; handler.removeCallbacks(deliver) }
    }

    private fun changed() {
        if (!observing) return
        dirty = true
        handler.removeCallbacks(deliver)
        handler.postDelayed(deliver, 500)
    }

    private fun drain() {
        if (!observing || running || !dirty) return
        dirty = false
        running = true
        worker.execute {
            val wake = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "mosh:network-change")
            val code = try { wake.acquire(10_000); MoshNative.notifyNetworkChanged() }
                catch (_: LinkageError) { -2 } catch (_: RuntimeException) { -4 }
                finally { if (wake.isHeld) wake.release() }
            handler.post {
                running = false
                if (code == -2 || code == -4) unavailable()
                if (dirty && observing) handler.postDelayed(deliver, 500)
            }
        }
    }
}
