package app.mosh.mosh

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build

/** User-requested OS exits require a real Activity reopen, never an alarm/retry. */
internal class MoshWaitingSystemStop(private val context: Context) {
    private val preferences = context.getSharedPreferences("app.mosh.systemstop.v1", Context.MODE_PRIVATE)

    fun blocked(): Boolean {
        if (Build.VERSION.SDK_INT < 33 || manuallyReopened) return false
        return try {
            val acknowledged = preferences.getLong("acknowledgedExit", 0)
            latestUserExit() > acknowledged
        } catch (_: RuntimeException) { true }
    }

    fun reopened() {
        manuallyReopened = true
        if (Build.VERSION.SDK_INT < 33) return
        try {
            check(preferences.edit().putLong("acknowledgedExit", latestUserExit()).commit())
        } catch (_: RuntimeException) { /* Failure retains the automatic-start fence. */ }
    }

    @android.annotation.TargetApi(30)
    private fun latestUserExit(): Long = context.getSystemService(ActivityManager::class.java)
        .getHistoricalProcessExitReasons(context.packageName, 0, 16)
        .filter { it.reason == ApplicationExitInfo.REASON_USER_REQUESTED }
        .maxOfOrNull { it.timestamp } ?: 0

    companion object { private var manuallyReopened = false }
}
