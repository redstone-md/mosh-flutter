package app.mosh.mosh

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class MoshWaitingChannel(messenger: BinaryMessenger, private val owner: MoshWaiting) {
    private val channel = MethodChannel(messenger, "app.mosh.mosh/waiting")

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                val value = when (call.method) {
                    "status" -> owner.status()
                    "enable" -> owner.enable()
                    "stop" -> owner.stop()
                    "setUserWork" -> owner.setUserWork(call.arguments as Map<*, *>)
                    "setNotificationPolicy" -> owner.setNotificationPolicy(call.arguments as Map<*, *>)
                    "publishNotification" -> owner.publishNotification(call.arguments as Map<*, *>)
                    "startupFailed" -> owner.startupFailed(call.arguments as Map<*, *>)
                    "requestBatteryExemption" -> owner.requestBatteryExemption()
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(value)
            } catch (_: RuntimeException) {
                result.error("WAITING_UNAVAILABLE", "Background availability could not be updated", null)
            }
        }
    }

    fun publish(value: Map<String, Any?>) { channel.invokeMethod("waitingStateChanged", value) }
}
