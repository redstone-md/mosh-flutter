package app.mosh.mosh

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/** Reduces disclosure against current native state immediately before OS publication. */
internal class MoshWaitingNotifications(
    private val context: Context,
    private val policy: MoshWaitingPolicy,
    private val accessAllowed: () -> Boolean,
) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    fun allowed(): Boolean = try {
        manager.areNotificationsEnabled() &&
            manager.getNotificationChannel(MESSAGES)?.importance != NotificationManager.IMPORTANCE_NONE
    } catch (_: RuntimeException) { false }

    fun publish(arguments: Map<*, *>): String {
        if (!allowed()) return "blocked"
        require(arguments["kind"] == "message")
        val id = arguments["id"] as? String ?: error("Missing notification id")
        require(id.matches(Regex("background-[0-9a-f]{32}")))
        val revision = integer(arguments["revision"])
        val count = integer(arguments["messageCount"]).coerceIn(1, Int.MAX_VALUE.toLong()).toInt()
        val tag = "$TAG$id"
        val existing = manager.activeNotifications.firstOrNull { it.tag == tag && it.id == MESSAGE_ID }
        if (existing != null && existing.notification.extras.getLong(REVISION) > revision) return "posted"
        return try {
            val notification = build(arguments["sender"] as? String, arguments["text"] as? String, count)
            notification.extras.putLong(REVISION, revision)
            manager.notify(tag, MESSAGE_ID, notification)
            "posted"
        } catch (_: SecurityException) { "blocked" }
        catch (_: RuntimeException) { "failed" }
    }

    fun refreshPrivacy() {
        try {
            for (entry in manager.activeNotifications) {
                if (entry.id != MESSAGE_ID || entry.tag?.startsWith(TAG) != true) continue
                val old = entry.notification
                val notification = build(old.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
                    old.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(), old.number)
                notification.extras.putLong(REVISION, old.extras.getLong(REVISION))
                manager.notify(entry.tag, entry.id, notification)
            }
        } catch (_: RuntimeException) {
            // Disclosure failure must not preserve stale protected OS fields.
            try {
                manager.activeNotifications.filter { it.tag?.startsWith(TAG) == true }
                    .forEach { manager.cancel(it.tag, it.id) }
            } catch (_: RuntimeException) { /* The OS no longer permits access/publication. */ }
        }
    }

    private fun build(sender: String?, text: String?, count: Int): Notification {
        val allowed = try { accessAllowed() } catch (_: RuntimeException) { false }
        val locked = context.getSystemService(KeyguardManager::class.java).isDeviceLocked
        val names = policy.namesAllowed(allowed, locked)
        val messages = policy.textAllowed(allowed, locked)
        val generic = MoshNotificationFactory.message(context, "Mosh", context.getString(R.string.mosh_new_message), count)
        val notification = MoshNotificationFactory.message(context,
            if (names) clean(sender) ?: "Mosh" else "Mosh",
            if (messages) clean(text, 8192) ?: context.getString(R.string.mosh_new_message)
            else context.getString(R.string.mosh_new_message), count)
        return Notification.Builder.recoverBuilder(context, notification)
            .setVisibility(if (locked && (names || messages)) Notification.VISIBILITY_PUBLIC else Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(generic).build()
    }

    private fun clean(value: String?, limit: Int = 240): String? = value?.replace(Regex("[\\p{Cc}&&[^\\n\\t]]"), "")
        ?.take(limit)?.takeIf { it.isNotBlank() }

    companion object {
        const val MESSAGES = "mosh_notifications"
        const val WAITING = "mosh_waiting"
        const val FOREGROUND_ID = 1
        private const val MESSAGE_ID = 2
        private const val TAG = "mosh.delivery."
        private const val REVISION = "mosh.deliveryRevision"

        fun ongoing(context: Context, label: Int = R.string.mosh_waiting_starting): Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(WAITING,
                context.getString(R.string.mosh_waiting_channel), NotificationManager.IMPORTANCE_LOW).apply {
                setSound(null, null); enableVibration(false); setShowBadge(false)
            })
            val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val stop = PendingIntent.getService(context, 1,
                Intent(context, MoshWaitingService::class.java).setAction(MoshWaitingService.STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            return Notification.Builder(context, WAITING).setSmallIcon(R.drawable.ic_stat_mosh)
                .setContentTitle("Mosh").setContentText(context.getString(label))
                .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_SERVICE).setVisibility(Notification.VISIBILITY_PUBLIC)
                .addAction(Notification.Action.Builder(null, context.getString(R.string.mosh_waiting_stop), stop).build())
                .build()
        }

        fun integer(value: Any?): Long {
            require(value is Int || value is Long)
            return (value as Number).toLong().also { require(it >= 0) }
        }
    }
}
