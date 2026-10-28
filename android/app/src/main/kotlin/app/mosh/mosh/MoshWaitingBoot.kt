package app.mosh.mosh

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.UserManager

/** Credential-encrypted boot path; neither Direct Boot nor a user-stop watchdog. */
class MoshWaitingBoot : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!context.getSystemService(UserManager::class.java).isUserUnlocked) return
        if (MoshWaitingSystemStop(context).blocked()) return
        try {
            if (MoshWaitingPolicy(MoshWaitingPreferences(context)).shouldWait()) {
                context.startForegroundService(Intent(context, MoshWaitingService::class.java))
            }
        } catch (_: RuntimeException) { /* Current restrictions are reported on the next real reopen. */ }
        try {
            if (Build.VERSION.SDK_INT < 34 && MoshTransferRecoveryStore(context).snapshot().isNotEmpty()) {
                context.startForegroundService(Intent(context, MoshTransferLegacyService::class.java))
            }
        } catch (_: RuntimeException) { /* Opaque intent survives; no restart watchdog is scheduled. */ }
    }
}
