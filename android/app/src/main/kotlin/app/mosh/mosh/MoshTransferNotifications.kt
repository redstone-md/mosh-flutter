package app.mosh.mosh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context

internal object MoshTransferNotifications {
    const val LEGACY_ID = 3
    private const val CHANNEL = "mosh_transfers"

    fun build(context: Context, id: String, direction: String,
        completed: Long = 0, total: Long = 0, paused: Boolean = false): Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL,
            context.getString(R.string.mosh_transfer_channel), NotificationManager.IMPORTANCE_LOW).apply {
            setSound(null, null); enableVibration(false); setShowBadge(false)
        })
        val label = when {
            paused -> R.string.mosh_transfer_paused
            direction == "upload" -> R.string.mosh_transfer_upload
            else -> R.string.mosh_transfer_download
        }
        val open = MoshTransferIntents.open(context, id)
        val percent = if (total > 0) (completed.toDouble() / total * 100).toInt().coerceIn(0, 100) else 0
        return Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_stat_mosh)
            .setContentTitle("Mosh").setContentText(context.getString(label))
            .setContentIntent(open).setOnlyAlertOnce(true).setOngoing(!paused)
            .setVisibility(Notification.VISIBILITY_PUBLIC).setCategory(Notification.CATEGORY_PROGRESS)
            .setProgress(if (paused) 0 else 100, percent, !paused && total == 0L)
            .addAction(Notification.Action.Builder(null,
                context.getString(if (paused) R.string.mosh_transfer_resume else android.R.string.cancel),
                MoshTransferIntents.action(context, id, paused)).build()).build()
    }

    fun paused(context: Context, id: String, direction: String) {
        try { context.getSystemService(NotificationManager::class.java)
            .notify("mosh.transfer.paused.$id", 4, build(context, id, direction, paused = true)) }
        catch (_: RuntimeException) { /* Notification permission can be withdrawn while work stops. */ }
    }

    fun clearPaused(context: Context, id: String) {
        try { context.getSystemService(NotificationManager::class.java).cancel("mosh.transfer.paused.$id", 4) }
        catch (_: RuntimeException) { /* Native state remains authoritative. */ }
    }
}
