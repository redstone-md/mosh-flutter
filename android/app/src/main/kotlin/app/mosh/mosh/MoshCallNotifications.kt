package app.mosh.mosh

import android.app.NotificationManager
import android.app.NotificationChannel
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/** Exact OS identity/revision and deadline; current native state remains authoritative. */
internal class MoshCallNotifications(private val context: Context, policy: MoshWaitingPolicy,
    accessAllowed: () -> Boolean, private val ringtone: MoshRingtone, private val empty: () -> Unit) {
    private data class Entry(val value: Map<*, *>, val revision: Long, val deadline: Long)
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val builder = MoshCallNotificationBuilder(context, policy, accessAllowed)
    private val handler = Handler(Looper.getMainLooper())
    private val entries = linkedMapOf<String, Entry>()
    private val latest = linkedMapOf<String, Long>()
    private val expiry = Runnable { expire() }
    val hasCalls: Boolean get() = entries.isNotEmpty()

    init {
        manager.createNotificationChannel(NotificationChannel(MoshWaitingNotifications.MESSAGES,
            context.getString(R.string.mosh_notification_channel), NotificationManager.IMPORTANCE_HIGH))
    }

    fun publish(value: Map<*, *>): String {
        val id = value["id"] as? String ?: error("Missing call id")
        require(id.matches(Regex("background-call-[0-9a-f]{32}")))
        val revision = MoshWaitingNotifications.integer(value["revision"])
        val phase = value["phase"] as? String
        require(phase in setOf("incoming", "outgoing", "accepting", "active", "ended"))
        val previousRevision = maxOf(latest[id] ?: -1, entries[id]?.revision ?: -1)
        if (revision < previousRevision || revision == previousRevision && id !in entries) return "posted"
        val timeout = MoshWaitingNotifications.integer(value["expiresAtMs"])
        val remaining = (timeout - System.currentTimeMillis()).coerceIn(0, 30_000)
        if (phase == "ended" || phase == "incoming" && remaining == 0L) {
            remove(id)
            remember(id, revision)
            return "posted"
        }
        if (!manager.areNotificationsEnabled() ||
            manager.getNotificationChannel(MoshWaitingNotifications.MESSAGES)?.importance == NotificationManager.IMPORTANCE_NONE) return "blocked"
        if (id !in entries && entries.size >= 16) return "failed"
        return try {
            val previous = entries[id]?.deadline ?: Long.MAX_VALUE
            val deadline = if (phase == "incoming") minOf(previous, SystemClock.elapsedRealtime() + remaining) else 0
            val entry = Entry(value.toMap(), revision, deadline)
            show(id, entry)
            entries[id] = entry
            remember(id, revision)
            if (phase == "incoming" && canRing()) ringtone.incoming(id, deadline - SystemClock.elapsedRealtime())
            else ringtone.stopIncoming(id)
            schedule()
            "posted"
        } catch (_: SecurityException) { "blocked" }
        catch (_: RuntimeException) { "failed" }
    }

    fun refreshPrivacy() {
        for ((id, entry) in entries.toMap()) {
            try { show(id, entry) } catch (_: RuntimeException) { remove(id) }
        }
    }

    private fun show(id: String, entry: Entry) {
        val remaining = if (entry.deadline > 0) (entry.deadline - SystemClock.elapsedRealtime()).coerceAtLeast(1) else 0
        val notification = builder.build(entry.value, remaining)
        notification.extras.putLong("mosh.deliveryRevision", entry.revision)
        manager.notify("mosh.call.$id", 3, notification)
    }

    private fun canRing(): Boolean = manager.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL ||
        manager.getNotificationChannel(MoshWaitingNotifications.MESSAGES)?.canBypassDnd() == true

    private fun remove(id: String) {
        ringtone.stopIncoming(id)
        try { manager.cancel("mosh.call.$id", 3) } catch (_: RuntimeException) { /* OS expiry still bounds the incoming alert. */ }
        entries.remove(id)
        schedule()
        if (entries.isEmpty()) empty()
    }

    private fun remember(id: String, revision: Long) {
        latest[id] = revision
        while (latest.size > 64) latest.remove(latest.keys.first())
    }

    private fun expire() {
        val now = SystemClock.elapsedRealtime()
        entries.filterValues { it.deadline > 0 && it.deadline <= now }.keys.toList().forEach(::remove)
        schedule()
    }

    private fun schedule() {
        handler.removeCallbacks(expiry)
        val next = entries.values.map { it.deadline }.filter { it > 0 }.minOrNull() ?: return
        handler.postDelayed(expiry, (next - SystemClock.elapsedRealtime()).coerceAtLeast(1))
    }
}
