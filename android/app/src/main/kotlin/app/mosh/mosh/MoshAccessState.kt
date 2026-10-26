package app.mosh.mosh

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

/** Durable non-secret access preferences, separate from all key storage. */
internal class MoshAccessState(context: Context) {
    private val preferences = context.getSharedPreferences("app.mosh.access.v1", Context.MODE_PRIVATE)
    private val clock = object : MoshAccessPolicy.Clock {
        override fun elapsed() = SystemClock.elapsedRealtime()
        override fun boot(): Int? = try {
            Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
                .takeIf { it >= 0 }
        } catch (_: Exception) { null }
    }
    val policy = MoshAccessPolicy(object : MoshAccessPolicy.Store {
        override fun read(): MoshAccessPolicy.Record? {
            return try { readStored() } catch (_: Exception) {
                // Broken non-secret metadata is never a grant. Authentication
                // can replace it durably; encrypted key storage is untouched.
                MoshAccessPolicy.Record(60, null, null, "locked")
            }
        }

        private fun readStored(): MoshAccessPolicy.Record? {
            if (preferences.all.isEmpty()) return null
            check(preferences.getInt("version", -1) == 1)
            return MoshAccessPolicy.Record(
                preferences.getInt("delaySeconds", 60),
                preferences.getInt("bootCount", -1).takeIf { it >= 0 },
                if (preferences.contains("deadlineElapsedMs")) preferences.getLong("deadlineElapsedMs", -1) else null,
                preferences.getString("state", "locked")!!)
        }

        override fun write(value: MoshAccessPolicy.Record) {
            val edit = preferences.edit().putInt("version", 1)
                .putInt("delaySeconds", value.delaySeconds).putString("state", value.state)
            if (value.bootCount == null) edit.remove("bootCount") else edit.putInt("bootCount", value.bootCount)
            if (value.deadlineElapsedMs == null) edit.remove("deadlineElapsedMs")
            else edit.putLong("deadlineElapsedMs", value.deadlineElapsedMs)
            check(edit.commit()) { "Access preferences unavailable" }
        }
    }, clock)

    fun snapshot(): Map<String, Any?> {
        val value = policy.snapshot()
        return mapOf("version" to 1, "delaySeconds" to value.delaySeconds,
            "bootCount" to value.bootCount, "deadlineElapsedMs" to value.deadlineElapsedMs,
            "state" to value.state, "elapsedRealtimeMs" to clock.elapsed(), "allowed" to policy.allowed())
    }

    fun save(value: Map<*, *>, foreground: Boolean) {
        require(value["version"] == 1)
        val delay = value["delaySeconds"] as? Int ?: error("Invalid delay")
        val requested = value["state"] as? String ?: error("Invalid access state")
        val deadline = value["deadlineElapsedMs"]
        require(deadline == null || deadline is Long || deadline is Int)
        require(requested in setOf("locked", "interactive", "grace"))
        require(value["bootCount"] == clock.boot())
        policy.setDelay(delay)
        policy.applyUiState(requested, foreground)
    }
}
