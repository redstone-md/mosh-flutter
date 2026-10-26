package app.mosh.mosh

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** One retained execution adapter. Native work facts never become user intent. */
internal class MoshWaiting(private val context: Context, messenger: BinaryMessenger,
    private val access: MoshAccess, ringtone: MoshRingtone) {
    private val policy = MoshWaitingPolicy(MoshWaitingPreferences(context))
    private val execution = MoshWaitingExecution()
    private val notifications = MoshWaitingNotifications(context, policy, access::disclosureAllowed)
    private val channel = MoshWaitingChannel(messenger, this)
    private val network = MoshWaitingNetwork(context) { restriction = "networkChangeUnavailable"; publish() }
    private var activity: MainActivity? = null
    private var resumed = false
    private var revision = 0L
    private var restriction: String? = null
    private val calls = MoshWaitingCalls(context, policy, access, ringtone, { resumed && activity != null }) {
        channel.callActionsChanged()
        publish()
    }
    private val media = MoshWaitingMedia(context, { calls.interactive }, ::start)
    val interactive: Boolean get() = resumed && activity != null &&
        context.getSystemService(PowerManager::class.java).isInteractive &&
        !context.getSystemService(KeyguardManager::class.java).isDeviceLocked

    init { access.disclosureChanged = {
        execution.changed(); notifications.refreshPrivacy(); calls.refreshPrivacy(); publish()
    } }

    fun attach(value: MainActivity) { activity = value; calls.attach(value) }
    fun detach(value: MainActivity) {
        if (activity !== value) return
        activity = null
        calls.detach(value)
        paused()
    }

    fun resumed() {
        resumed = true
        execution.changed()
        if (restriction in setOf("keyUnavailable", "nativeUnavailable")) restriction = null
        if (policy.shouldWait() && !MoshWaitingService.running) start()
        publish()
    }

    fun paused() { resumed = false; media.paused(); execution.changed(); publish() }

    fun enable(): Map<String, Any?> {
        check(interactive) { "Waiting requires foreground setup" }
        policy.enable()
        restriction = null
        execution.changed()
        start()
        publish()
        return status()
    }

    fun stop(): Map<String, Any?> {
        try { policy.stop() }
        finally { execution.changed(); publish() }
        // Fresh post-intent native facts release the service after user work.
        return status()
    }

    fun serviceChanged() {
        execution.changed()
        network.observe(MoshWaitingService.running)
        media.serviceChanged()
        publish()
    }

    fun setUserWork(value: Map<*, *>): Map<String, Any?> {
        val accepted = execution.accept(MoshWaitingNotifications.integer(value["intentRevision"]),
            value["actualMode"] as? String ?: error("Missing mode"),
            count(value["currentCalls"]), count(value["currentUserTransfers"]))
        if (accepted) {
            calls.work(count(value["currentCalls"]))
            if (count(value["currentCalls"]) == 0) MoshWaitingService.mediaTypes(false, false)
            val reachability = value["reachability"] as? String ?: "unavailable"
            if (!policy.snapshot().waitingEnabled && execution.canRelease(interactive)) {
                MoshWaitingService.finishWaiting()
            } else MoshWaitingService.updateStatus(reachability == "ready",
                value["limitation"] != null || status()["restriction"] != null, count(value["currentCalls"]) > 0)
        }
        return status()
    }

    fun setNotificationPolicy(value: Map<*, *>): Map<String, Any?> {
        check(interactive)
        try {
            policy.notificationPolicy(value["showNamesWhenLocked"] as? Boolean ?: error("Invalid names policy"),
                value["showTextWhenLocked"] as? Boolean ?: error("Invalid text policy"))
        } finally { notifications.refreshPrivacy(); publish() }
        return status()
    }

    fun publishNotification(value: Map<*, *>): String =
        if (value["kind"] == "call") calls.publish(value) else notifications.publish(value)

    fun callIntent(intent: Intent) = calls.accept(intent)
    fun takeCallActions() = calls.take()
    fun setMediaTypes(value: Map<*, *>, result: MethodChannel.Result) {
        if (value["microphone"] == true || value["camera"] == true) {
            execution.changed()
            publish()
        }
        media.set(value, result)
    }

    fun startupFailed(value: Map<*, *>): Map<String, Any?> {
        val reason = value["reason"] as? String
        require(reason in setOf("keyUnavailable", "nativeUnavailable"))
        if (MoshWaitingNotifications.integer(value["intentRevision"]) == execution.revision()) {
            restriction = reason
            MoshWaitingService.finishWaiting()
            publish()
        }
        return status()
    }

    fun requestBatteryExemption(): Map<String, Any?> {
        val owner = activity
        check(interactive && owner != null)
        val power = context.getSystemService(PowerManager::class.java)
        if (!power.isIgnoringBatteryOptimizations(context.packageName)) {
            val first = policy.offerBatteryExemption()
            val intent = if (first) Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}"))
                else Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            try { owner.startActivity(intent) }
            catch (_: RuntimeException) { restriction = "batterySettingsUnavailable" }
        }
        publish()
        return status()
    }

    fun status(): Map<String, Any?> {
        val choice = policy.snapshot()
        val exempt = context.getSystemService(PowerManager::class.java)
            .isIgnoringBatteryOptimizations(context.packageName)
        val allowed = notifications.allowed()
        return mapOf("revision" to ++revision, "intentRevision" to execution.revision(),
            "interactive" to interactive, "waitingEnabled" to choice.waitingEnabled,
            "callInteractive" to calls.interactive,
            "serviceRunning" to MoshWaitingService.running, "setupComplete" to choice.setupComplete,
            "notificationsAllowed" to allowed, "batteryExempt" to exempt,
            "batteryExemptionOffered" to choice.batteryExemptionOffered,
            "showNamesWhenLocked" to choice.showNamesWhenLocked, "showTextWhenLocked" to choice.showTextWhenLocked,
            "restriction" to when {
                policy.storageUnavailable() -> "storageUnavailable"
                restriction != null -> restriction
                !allowed -> "notificationsDenied"
                !exempt -> "batteryRestricted"
                else -> null
            })
    }

    private fun start() {
        if (MoshWaitingService.running) return
        try { context.startForegroundService(Intent(context, MoshWaitingService::class.java)) }
        catch (_: RuntimeException) { restriction = "serviceStartRestricted" }
    }

    private fun publish() { channel.publish(status()) }

    private fun count(value: Any?): Int = MoshWaitingNotifications.integer(value)
        .also { require(it <= Int.MAX_VALUE) }.toInt()
}
