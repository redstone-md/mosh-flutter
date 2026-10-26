package app.mosh.mosh

import android.content.Context

/** Non-secret installation choices survive service/process reclamation. */
internal class MoshWaitingPreferences(context: Context) : MoshWaitingPolicy.Store {
    private val preferences = context.getSharedPreferences("app.mosh.waiting.v1", Context.MODE_PRIVATE)

    override fun read(): MoshWaitingPolicy.Record? {
        if (preferences.all.isEmpty()) return null
        check(preferences.getInt("version", -1) == 1)
        return MoshWaitingPolicy.Record(
            preferences.getBoolean("setupComplete", false),
            preferences.getBoolean("waitingEnabled", false),
            preferences.getBoolean("batteryExemptionOffered", false),
            preferences.getBoolean("showNamesWhenLocked", false),
            preferences.getBoolean("showTextWhenLocked", false))
    }

    override fun write(value: MoshWaitingPolicy.Record) {
        check(preferences.edit().putInt("version", 1)
            .putBoolean("setupComplete", value.setupComplete)
            .putBoolean("waitingEnabled", value.waitingEnabled)
            .putBoolean("batteryExemptionOffered", value.batteryExemptionOffered)
            .putBoolean("showNamesWhenLocked", value.showNamesWhenLocked)
            .putBoolean("showTextWhenLocked", value.showTextWhenLocked).commit()) {
            "Waiting preferences unavailable"
        }
    }
}
