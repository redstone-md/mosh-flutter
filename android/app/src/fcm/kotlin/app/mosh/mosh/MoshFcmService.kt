package app.mosh.mosh

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Wake pushes through FCM (mosh-wake/README.md, ADR 0055). A call starts Mosh
 * in the background to take the caller's offer, which rings as with background
 * waiting. A message shows the chat's name and text opened from its sealed
 * preview, or "New message", under the lock screen settings. While Mosh is
 * connected its own delivery shows the message, so the push shows nothing.
 * Every other push ends in a notification, as FCM expects of high priority.
 */
class MoshFcmService : FirebaseMessagingService() {
    override fun onRegistered(installationId: String) {
        (application as MoshApplication).existingRuntime?.wake?.tokensChanged()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (connected()) return
        when (message.data["kind"]) {
            "call" -> MoshWaitingService.wake(this)
            "message" -> opened(message.data["preview"]).let { shown ->
                MoshWaitingNotifications.standalone(this).publishWoken(shown?.chat, shown?.title, shown?.text)
            }
        }
    }

    private fun opened(preview: String?): MoshPreviewBook.Shown? {
        if (preview == null) return null
        val chats = try { MoshWake.previews(this) } catch (_: Exception) { null } ?: return null
        return MoshPreviewBook.parse(chats)?.open(preview)
    }

    /** Mosh runs with Moss: on screen, or waiting in the background. */
    private fun connected(): Boolean {
        val runtime = (application as MoshApplication).existingRuntime ?: return false
        return runtime.engine.dartExecutor.isExecutingDart && (MoshWaitingService.running || runtime.waiting.interactive)
    }
}
