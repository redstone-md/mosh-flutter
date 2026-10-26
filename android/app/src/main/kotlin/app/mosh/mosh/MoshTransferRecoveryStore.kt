package app.mosh.mosh

import android.content.Context
import android.os.UserManager

/** Credential-encrypted opaque OS intents, independent of the saved waiting choice. */
internal class MoshTransferRecoveryStore(private val context: Context) {
    fun admit(id: String, direction: String) = access { it.admit(id, direction) }
    fun forget(id: String) = access { it.forget(id) }
    fun retain(current: Set<String>) = access { it.retain(current) }
    fun snapshot(): List<MoshTransferRecovery.Entry> = access { it.snapshot() }

    private fun <T> access(operation: (MoshTransferRecovery) -> T): T = synchronized(LOCK) {
        check(!context.isDeviceProtectedStorage && context.getSystemService(UserManager::class.java).isUserUnlocked)
        val preferences = context.getSharedPreferences("app.mosh.transfer-recovery.v1", Context.MODE_PRIVATE)
        operation(MoshTransferRecovery(object : MoshTransferRecovery.Store {
            override fun read() = preferences.getString("pending", "") ?: ""
            override fun write(value: String) {
                check(preferences.edit().putString("pending", value).commit()) { "Transfer recovery save refused" }
            }
        }))
    }

    companion object { private val LOCK = Any() }
}
