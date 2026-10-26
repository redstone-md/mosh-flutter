package app.mosh.mosh

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.UserManager
import android.os.PowerManager

/** OS execution eligibility for the existing application runtime, never a second owner. */
class MoshWaitingService : Service() {
    private val startupWake by lazy {
        getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,
            "mosh:waiting-startup").apply { setReferenceCounted(false) }
    }
    override fun onCreate() {
        super.onCreate()
        try {
            val notification = MoshWaitingNotifications.ongoing(this)
            if (Build.VERSION.SDK_INT >= 29) startForeground(MoshWaitingNotifications.FOREGROUND_ID,
                notification, if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0)
            else startForeground(MoshWaitingNotifications.FOREGROUND_ID, notification)
            current = this
            (application as MoshApplication).existingRuntime?.waiting?.serviceChanged()
        } catch (_: RuntimeException) { stopSelf() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (current !== this) return START_NOT_STICKY
        val application = application as MoshApplication
        if (intent?.action == MoshCallIntents.CONTROL) {
            if (MoshCallIntents.capability(intent) == null) { finishWaiting(); return START_NOT_STICKY }
            try {
                val runtime = application.runtime
                runtime.waiting.serviceChanged()
                runtime.waiting.callIntent(intent)
                runtime.startInBackground()
            } catch (_: RuntimeException) { finishWaiting() }
            catch (_: LinkageError) { finishWaiting() }
            return START_NOT_STICKY
        }
        if (intent?.action == STOP) {
            val owner = application.existingRuntime
            if (owner != null && owner.engine.dartExecutor.isExecutingDart) {
                try { owner.waiting.stop() }
                catch (_: RuntimeException) { /* Published storage restriction; no successful acknowledgement. */ }
            }
            else {
                try { MoshWaitingPolicy(MoshWaitingPreferences(this)).stop() }
                catch (_: RuntimeException) { /* No running owner/work to retain on storage failure. */ }
                finally { finishWaiting() }
            }
            return START_NOT_STICKY
        }
        if (!eligible()) {
            if (application.existingRuntime?.engine?.dartExecutor?.isExecutingDart != true) finishWaiting()
            else application.existingRuntime?.waiting?.serviceChanged()
            return START_NOT_STICKY
        }
        try {
            startupWake.acquire(15_000)
            val runtime = application.runtime
            runtime.waiting.serviceChanged()
            runtime.startInBackground()
        } catch (_: RuntimeException) { finishWaiting(); return START_NOT_STICKY }
        catch (_: LinkageError) { finishWaiting(); return START_NOT_STICKY }
        return START_STICKY
    }

    private fun eligible(): Boolean {
        if (getSystemService(UserManager::class.java).isUserUnlocked != true) return false
        if (MoshWaitingSystemStop(this).blocked()) return false
        return MoshWaitingPolicy(MoshWaitingPreferences(this)).shouldWait()
    }

    override fun onDestroy() {
        if (startupWake.isHeld) startupWake.release()
        if (current === this) {
            current = null
            (application as MoshApplication).existingRuntime?.waiting?.serviceChanged()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val STOP = "app.mosh.mosh.STOP_WAITING"
        private var current: MoshWaitingService? = null
        val running: Boolean get() = current != null

        fun mediaTypes(microphone: Boolean, camera: Boolean): Boolean {
            val service = current ?: return !microphone && !camera
            return try {
                val base = if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
                var types = base
                if (Build.VERSION.SDK_INT >= 30) {
                    if (microphone) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    if (camera) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                }
                val label = if (microphone || camera) R.string.mosh_call_active else R.string.mosh_waiting_starting
                val notification = MoshWaitingNotifications.ongoing(service, label)
                if (Build.VERSION.SDK_INT >= 29) service.startForeground(MoshWaitingNotifications.FOREGROUND_ID, notification, types)
                else service.startForeground(MoshWaitingNotifications.FOREGROUND_ID, notification)
                true
            } catch (_: RuntimeException) { false }
        }

        fun finishWaiting() {
            current?.let { service ->
                service.stopForeground(STOP_FOREGROUND_REMOVE)
                service.stopSelf()
            }
        }

        fun updateStatus(ready: Boolean, limited: Boolean, inCall: Boolean = false) {
            current?.let { service ->
                if (service.startupWake.isHeld) service.startupWake.release()
                val label = when {
                    inCall -> R.string.mosh_call_active
                    limited -> R.string.mosh_waiting_limited
                    ready -> R.string.mosh_waiting_ready
                    else -> R.string.mosh_waiting_starting
                }
                val notification = MoshWaitingNotifications.ongoing(service, label)
                try {
                    service.getSystemService(android.app.NotificationManager::class.java)
                        .notify(MoshWaitingNotifications.FOREGROUND_ID, notification)
                } catch (_: RuntimeException) { /* The execution owner still reports actual permission state. */ }
            }
        }
    }
}
