package app.mosh.mosh

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri

/** Transfer intents contain only random operation IDs, never file or chat metadata. */
internal object MoshTransferIntents {
    const val CANCEL = "app.mosh.mosh.CANCEL_TRANSFER"
    const val RESUME = "app.mosh.mosh.RESUME_TRANSFER"
    private const val OPEN = "app.mosh.mosh.OPEN_TRANSFER"
    const val ID = "transferId"
    private const val FLAGS = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    fun valid(id: String) = id.matches(Regex("transfer-[0-9a-f]{32}"))
    fun id(intent: Intent?): String? = try { intent?.getStringExtra(ID)?.takeIf(::valid) }
        catch (_: RuntimeException) { null }

    fun action(context: Context, id: String, resume: Boolean): PendingIntent {
        require(valid(id))
        if (resume) return activity(context, id, RESUME)
        val intent = Intent(context, MoshTransferControl::class.java).setAction(CANCEL)
            .setData(Uri.parse("mosh-transfer://cancel/$id"))
            .putExtra(ID, id)
        return PendingIntent.getBroadcast(context, 0, intent, FLAGS)
    }

    fun open(context: Context, id: String) = activity(context, id, OPEN)

    private fun activity(context: Context, id: String, action: String): PendingIntent {
        require(valid(id))
        return PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java)
            .setAction(action).setData(Uri.parse("mosh-transfer://$action/$id")).putExtra(ID, id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), FLAGS)
    }

    fun forFlutter(intent: Intent): Intent = if (intent.action in setOf(RESUME, CANCEL, OPEN))
        Intent(intent).setData(null) else intent
}

class MoshTransferControl : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = MoshTransferIntents.id(intent) ?: return
        if (intent.action != MoshTransferIntents.CANCEL) return
        try {
            val application = context.applicationContext as MoshApplication
            val runtime = application.runtime
            runtime.waiting.transfers.cancel(id)
            runtime.startInBackground()
        } catch (_: RuntimeException) { MoshTransferJobs(context).cancel(id) }
        catch (_: LinkageError) { MoshTransferJobs(context).cancel(id) }
    }
}
