package app.mosh.mosh

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.Person

/** AndroidX supplies CallStyle and its older-platform fallback; no second plugin. */
internal class MoshCallNotificationBuilder(private val context: Context,
    private val policy: MoshWaitingPolicy, private val accessAllowed: () -> Boolean) {
    fun build(value: Map<*, *>, remainingMs: Long): Notification {
        val locked = context.getSystemService(KeyguardManager::class.java).isDeviceLocked
        val allowed = try { accessAllowed() } catch (_: RuntimeException) { false }
        val name = if (policy.namesAllowed(allowed, locked)) clean(value["sender"] as? String) ?: "Mosh" else "Mosh"
        return content(value, remainingMs, name, true)
            .setVisibility(if (policy.snapshot().showNamesWhenLocked) NotificationCompat.VISIBILITY_PUBLIC
                else NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(content(value, remainingMs, "Mosh", false).build()).build()
    }

    private fun content(value: Map<*, *>, remainingMs: Long, name: String, fullScreen: Boolean): NotificationCompat.Builder {
        val phase = value["phase"] as String
        val caller = Person.Builder().setName(name).build()
        val builder = NotificationCompat.Builder(context, MoshWaitingNotifications.MESSAGES)
            .setSmallIcon(R.drawable.ic_stat_mosh).setContentTitle(name).setContentText(context.getString(label(phase)))
            .setCategory(NotificationCompat.CATEGORY_CALL).setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true).setOnlyAlertOnce(true).setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        val answer = value["answerCapability"] as? String
        if (phase == "incoming") {
            val accept = MoshCallIntents.activity(context, requireNotNull(answer), true)
            val decline = MoshCallIntents.control(context, value["declineCapability"] as String)
            val present = MoshCallIntents.activity(context, answer, false)
            builder.setStyle(NotificationCompat.CallStyle.forIncomingCall(caller, decline, accept))
                .setContentIntent(present).setTimeoutAfter(remainingMs)
            val manager = context.getSystemService(NotificationManager::class.java)
            if (fullScreen && (Build.VERSION.SDK_INT < 34 || manager.canUseFullScreenIntent())) builder.setFullScreenIntent(present, true)
        } else {
            val hangup = MoshCallIntents.control(context, value["hangupCapability"] as String)
            builder.setStyle(NotificationCompat.CallStyle.forOngoingCall(caller, hangup))
                .setContentIntent(PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        return builder
    }

    private fun label(phase: String): Int = when (phase) {
        "incoming" -> R.string.mosh_call_incoming
        "outgoing" -> R.string.mosh_call_outgoing
        "accepting" -> R.string.mosh_call_connecting
        else -> R.string.mosh_call_active
    }

    private fun clean(value: String?): String? = value?.replace(Regex("[\\p{Cc}&&[^\\n\\t]]"), "")
        ?.take(240)?.takeIf { it.isNotBlank() }
}
