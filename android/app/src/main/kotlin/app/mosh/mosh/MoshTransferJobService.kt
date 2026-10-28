package app.mosh.mosh

import android.app.NotificationManager
import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserManager

/** Gives the existing transfer worker a bounded OS lease; performs no transfer itself. */
class MoshTransferJobService : JobService() {
    private class Active(val parameters: JobParameters, val id: String, val direction: String) {
        var generation = 0L
        var observed = false
        var completed = -1L
        var total = -1L
    }
    private val active = mutableMapOf<Int, Active>()
    private val handler = Handler(Looper.getMainLooper())
    private val owner get() = (application as MoshApplication).existingRuntime?.waiting?.transfers

    override fun onStartJob(params: JobParameters): Boolean {
        val id = params.extras.getString(MoshTransferIntents.ID)?.takeIf(MoshTransferIntents::valid) ?: return false
        val direction = params.extras.getString("direction")?.takeIf { it in setOf("upload", "download") } ?: return false
        if (!getSystemService(UserManager::class.java).isUserUnlocked || MoshWaitingSystemStop(this).blocked()) return false
        val work = Active(params, id, direction)
        try {
            notification(work)
            val runtime = (application as MoshApplication).runtime
            work.generation = runtime.waiting.transfers.started(id, direction,
                { facts -> progress(work, facts) }, { finish(work) }) ?: run {
                clearNotification(work); return false
            }
            active[params.jobId] = work
            runtime.startInBackground()
            handler.postDelayed({
                if (active[params.jobId] === work && !work.observed) {
                    owner?.stopped(id, work.generation, "unavailable")
                    finish(work)
                }
            }, 30_000)
            return true
        } catch (_: RuntimeException) { failed(work) }
        catch (_: LinkageError) { failed(work) }
        return false
    }

    override fun onStopJob(params: JobParameters): Boolean {
        val work = active[params.jobId]?.takeIf { it.parameters === params } ?: return false
        val userStopped = Build.VERSION.SDK_INT >= 31 && params.stopReason == JobParameters.STOP_REASON_USER
        owner?.stopped(work.id, work.generation, if (userStopped) "userStopped" else "constraints")
        active.remove(params.jobId)
        clearNotification(work)
        if (!userStopped) MoshTransferNotifications.paused(this, work.id, work.direction)
        return !userStopped
    }

    override fun onDestroy() {
        for (work in active.values.toList()) {
            owner?.stopped(work.id, work.generation, "unavailable")
            clearNotification(work)
        }
        active.clear()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun progress(work: Active, facts: Map<*, *>) {
        if (active[work.parameters.jobId] !== work) return
        work.observed = true
        val completed = MoshWaitingNotifications.integer(facts["completedBytes"])
        val total = MoshWaitingNotifications.integer(facts["totalBytes"])
        if (work.completed == completed && work.total == total) return
        work.completed = completed
        work.total = total
        try { notification(work, completed, total) }
        catch (_: RuntimeException) { failed(work) }
    }

    private fun notification(work: Active, completed: Long = 0, total: Long = 0) {
        val notification = MoshTransferNotifications.build(this, work.id, work.direction, completed, total)
        if (Build.VERSION.SDK_INT >= 34) setNotification(work.parameters, work.parameters.jobId,
            notification, JOB_END_NOTIFICATION_POLICY_REMOVE)
        else getSystemService(NotificationManager::class.java).notify(work.parameters.jobId, notification)
    }

    private fun finish(work: Active) {
        if (active[work.parameters.jobId] !== work) return
        active.remove(work.parameters.jobId)
        clearNotification(work)
        jobFinished(work.parameters, false)
    }

    private fun failed(work: Active) {
        if (work.generation != 0L) owner?.stopped(work.id, work.generation, "unavailable")
        finish(work)
        clearNotification(work)
    }

    private fun clearNotification(work: Active) {
        try { getSystemService(NotificationManager::class.java).cancel(work.parameters.jobId) }
        catch (_: RuntimeException) { /* Notification access can be withdrawn by the OS. */ }
    }
}
