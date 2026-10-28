package app.mosh.mosh

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.PersistableBundle

/** OS scheduling only: acceptance is never treated as permission to send bytes. */
internal class MoshTransferJobs(private val context: Context) {
    private val scheduler = context.getSystemService(JobScheduler::class.java)
    private val component = ComponentName(context, MoshTransferJobService::class.java)

    fun schedule(id: String, direction: String, bytes: Long, userInitiated: Boolean): Boolean {
        val pending = scheduler.allPendingJobs
        val existing = pending.firstOrNull { it.service == component && it.extras.getString(MoshTransferIntents.ID) == id }
        if (existing != null && (!userInitiated || Build.VERSION.SDK_INT < 34 || existing.isUserInitiated)) return true
        if (pending.count { it.service == component } >= 32 && existing == null) return false
        val number = existing?.id ?: availableId(id, pending) ?: return false
        val extras = PersistableBundle().apply {
            putString(MoshTransferIntents.ID, id); putString("direction", direction)
        }
        val job = JobInfo.Builder(number, component).setExtras(extras)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true)
            .setBackoffCriteria(30_000, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
        if (Build.VERSION.SDK_INT >= 28) job.setEstimatedNetworkBytes(
            if (direction == "download") bytes else 0, if (direction == "upload") bytes else 0)
        if (Build.VERSION.SDK_INT >= 34 && userInitiated) job.setUserInitiated(true)
        return scheduler.schedule(job.build()) == JobScheduler.RESULT_SUCCESS
    }

    fun cancel(id: String) {
        scheduler.allPendingJobs.filter { it.service == component && it.extras.getString(MoshTransferIntents.ID) == id }
            .forEach { scheduler.cancel(it.id) }
    }

    private fun availableId(id: String, pending: List<JobInfo>): Int? {
        val start = 0x4d000000 or (id.hashCode() and 0x00ffffff)
        return (0 until 32).map { start + it }.firstOrNull { candidate -> pending.none { it.id == candidate } }
    }
}
