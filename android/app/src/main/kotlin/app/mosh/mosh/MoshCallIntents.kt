package app.mosh.mosh

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import java.security.MessageDigest

/** Immutable explicit intents carry one opaque capability and no conversation data. */
internal object MoshCallIntents {
    const val ANSWER = "app.mosh.mosh.ANSWER_CALL"
    const val PRESENT = "app.mosh.mosh.PRESENT_CALL"
    const val CONTROL = "app.mosh.mosh.CONTROL_CALL"
    private const val CAPABILITY = "capability"
    private const val FLAGS = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    fun activity(context: Context, capability: String, answer: Boolean): PendingIntent {
        require(valid(capability))
        val action = if (answer) ANSWER else PRESENT
        val intent = Intent(context, MainActivity::class.java).setAction(action)
            .setData(Uri.parse("mosh-call://$action/${identity(capability)}")).putExtra(CAPABILITY, capability)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, 0, intent, FLAGS)
    }

    fun control(context: Context, capability: String): PendingIntent {
        require(valid(capability))
        val intent = Intent(context, MoshWaitingService::class.java).setAction(CONTROL)
            .setData(Uri.parse("mosh-call://control/${identity(capability)}")).putExtra(CAPABILITY, capability)
        return PendingIntent.getForegroundService(context, 0, intent, FLAGS)
    }

    fun capability(intent: Intent): String? = try { intent.getStringExtra(CAPABILITY)?.takeIf(::valid) }
        catch (_: RuntimeException) { null }
    fun valid(value: String): Boolean = value.matches(Regex("[0-9a-f]{64}"))

    fun forFlutter(intent: Intent): Intent = if (intent.action in setOf(ANSWER, PRESENT, CONTROL))
        Intent(intent).setData(null) else intent

    // Intent identity appears in system diagnostics; the action secret stays in extras.
    private fun identity(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.US_ASCII)).joinToString("") { "%02x".format(it) }
}
