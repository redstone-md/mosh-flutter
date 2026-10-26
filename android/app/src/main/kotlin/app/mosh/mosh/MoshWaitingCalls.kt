package app.mosh.mosh

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.view.WindowManager

/** Call-only entry does not change the interactive chat policy or its deadline. */
internal class MoshWaitingCalls(private val context: Context, policy: MoshWaitingPolicy,
    private val access: MoshAccess, ringtone: MoshRingtone, private val resumed: () -> Boolean,
    private val changed: () -> Unit) {
    private val actions = MoshCallActions(SystemClock::elapsedRealtime)
    private var activity: MainActivity? = null
    private var userCall = false
    private val notifications = MoshCallNotifications(context, policy, access::disclosureAllowed, ringtone) {
        if (!userCall) window(false)
    }

    val interactive: Boolean get() = resumed() && context.getSystemService(PowerManager::class.java).isInteractive &&
        (!context.getSystemService(KeyguardManager::class.java).isDeviceLocked || access.callOnly)

    fun attach(value: MainActivity) { activity = value; if (access.callOnly) window(true) }
    fun detach(value: MainActivity) { if (activity === value) activity = null }

    fun accept(intent: Intent): Boolean {
        if (intent.action !in setOf(MoshCallIntents.ANSWER, MoshCallIntents.PRESENT, MoshCallIntents.CONTROL)) return false
        val capability = MoshCallIntents.capability(intent) ?: return false
        val answer = intent.action == MoshCallIntents.ANSWER
        if (!actions.offer(capability, answer)) return false
        if (intent.action != MoshCallIntents.CONTROL && context.getSystemService(KeyguardManager::class.java).isDeviceLocked) window(true)
        changed()
        return true
    }

    fun take(): List<Map<String, Any>> = actions.take().map {
        mapOf("capability" to it.capability, "interactiveAnswer" to it.interactiveAnswer)
    }

    fun publish(value: Map<*, *>): String = notifications.publish(value)
    fun work(count: Int) {
        userCall = count > 0
        if (!userCall && !notifications.hasCalls) window(false)
    }
    fun refreshPrivacy() {
        if (!access.callOnly) window(false)
        notifications.refreshPrivacy()
    }

    private fun window(callOnly: Boolean) {
        access.callOnly(callOnly)
        val owner = activity ?: return
        if (Build.VERSION.SDK_INT >= 27) {
            owner.setShowWhenLocked(callOnly)
            owner.setTurnScreenOn(callOnly)
        } else {
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (callOnly) owner.window.addFlags(flags) else owner.window.clearFlags(flags)
        }
    }
}
