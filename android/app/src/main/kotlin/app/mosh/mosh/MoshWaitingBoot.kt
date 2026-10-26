package app.mosh.mosh

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.UserManager

/** Credential-encrypted boot path; neither Direct Boot nor a user-stop watchdog. */
class MoshWaitingBoot : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!context.getSystemService(UserManager::class.java).isUserUnlocked) return
        val policy = MoshWaitingPolicy(MoshWaitingPreferences(context))
        if (!policy.shouldWait() || MoshWaitingSystemStop(context).blocked()) return
        try { context.startForegroundService(Intent(context, MoshWaitingService::class.java)) }
        catch (_: RuntimeException) { /* Current restrictions are reported on the next real reopen. */ }
    }
}
