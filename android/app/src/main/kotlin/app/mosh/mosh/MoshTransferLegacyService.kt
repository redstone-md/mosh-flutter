package app.mosh.mosh

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.UserManager

/** Pre-14 explicit user transfers share the retained worker under a dataSync service. */
class MoshTransferLegacyService : Service() {
    private class Active(val id: String, val direction: String) {
        var generation = 0L
        var completed = 0L
        var observed = false
    }
    private val active = linkedMapOf<String, Active>()
    private val handler = Handler(Looper.getMainLooper())
    private val owner get() = (application as MoshApplication).existingRuntime?.waiting?.transfers
    private val wake by lazy {
        getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,
            "mosh:user-transfer").apply { setReferenceCounted(false) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = MoshTransferIntents.id(intent)
        val direction = intent?.getStringExtra("direction")?.takeIf { it in setOf("upload", "download") }
        if (id == null || direction == null || Build.VERSION.SDK_INT >= 34 ||
            !getSystemService(UserManager::class.java).isUserUnlocked || MoshWaitingSystemStop(this).blocked()) {
            stopSelf(startId); return START_NOT_STICKY
        }
        if (active.containsKey(id)) return START_NOT_STICKY
        val work = Active(id, direction)
        try {
            promote(work)
            val runtime = (application as MoshApplication).runtime
            work.generation = runtime.waiting.transfers.started(id, direction,
                { facts -> progress(work, facts) }, { finish(work) }) ?: run {
                if (active.isEmpty()) stopSelf(startId)
                return START_NOT_STICKY
            }
            active[id] = work
            wake.acquire(120_000)
            runtime.startInBackground()
            handler.postDelayed({
                if (active[id] === work && !work.observed) {
                    owner?.stopped(id, work.generation, "unavailable"); finish(work)
                }
            }, 30_000)
        } catch (_: RuntimeException) { failed(work) }
        catch (_: LinkageError) { failed(work) }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        for (work in active.values.toList()) owner?.stopped(work.id, work.generation, "unavailable")
        active.clear()
        handler.removeCallbacksAndMessages(null)
        if (wake.isHeld) wake.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun progress(work: Active, facts: Map<*, *>) {
        if (active[work.id] !== work) return
        work.observed = true
        val completed = MoshWaitingNotifications.integer(facts["completedBytes"])
        val total = MoshWaitingNotifications.integer(facts["totalBytes"])
        if (completed > work.completed) { work.completed = completed; wake.acquire(120_000) }
        if (active.values.firstOrNull() === work) {
            try { promote(work, completed, total) }
            catch (_: RuntimeException) { failed(work) }
        }
    }

    private fun promote(work: Active, completed: Long = 0, total: Long = 0) {
        val notification = MoshTransferNotifications.build(this, work.id, work.direction, completed, total)
        if (Build.VERSION.SDK_INT >= 29) startForeground(MoshTransferNotifications.LEGACY_ID,
            notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(MoshTransferNotifications.LEGACY_ID, notification)
    }

    private fun finish(work: Active) {
        if (active[work.id] !== work) return
        active.remove(work.id)
        val next = active.values.firstOrNull()
        if (next != null) promote(next)
        else { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
    }

    private fun failed(work: Active) {
        if (work.generation != 0L) owner?.stopped(work.id, work.generation, "unavailable")
        finish(work)
        if (active.isEmpty()) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
    }
}
