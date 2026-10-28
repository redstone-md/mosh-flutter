package app.mosh.mosh

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper

/** Retained adapter for native transfer facts and actual OS execution callbacks. */
internal class MoshUserTransfers(private val context: Context,
    private val interactive: () -> Boolean, private val changed: () -> Unit,
    private val actionsChanged: () -> Unit) {
    private class Running(val generation: Long, val progress: (Map<*, *>) -> Unit, val finish: () -> Unit) {
        var completed = -1L
        var expiry: Runnable? = null
    }
    private val execution = MoshTransferExecution()
    private val running = mutableMapOf<String, Running>()
    private val jobs = MoshTransferJobs(context)
    private val recovery = MoshTransferRecoveryStore(context)
    private val handler = Handler(Looper.getMainLooper())
    val runningCount: Int get() = running.size
    private val actions by lazy {
        val preferences = context.getSharedPreferences("mosh_transfer_actions", Context.MODE_PRIVATE)
        MoshTransferActions(object : MoshTransferActions.Store {
            override fun read() = preferences.getString("pending", "") ?: ""
            override fun write(value: String) {
                check(preferences.edit().putString("pending", value).commit()) { "Transfer action save refused" }
            }
        })
    }

    fun begin(value: Map<*, *>, deferred: Boolean): Boolean {
        val id = value["id"] as? String ?: error("Missing transfer id")
        val direction = value["direction"] as? String
        require(MoshTransferIntents.valid(id) && direction in setOf("upload", "download"))
        val bytes = MoshWaitingNotifications.integer(value["estimatedBytes"])
        if (!deferred && !interactive() || actions.snapshot().any { it.id == id && it.action == "cancel" }) return false
        if (running.containsKey(id)) return true
        execution.scheduled(id)
        val accepted = try {
            if (!deferred && Build.VERSION.SDK_INT < 34) {
                if (!recovery.admit(id, direction!!)) return false
                context.startForegroundService(Intent(context, MoshTransferLegacyService::class.java)
                    .putExtra(MoshTransferIntents.ID, id).putExtra("direction", direction))
                true
            } else jobs.schedule(id, direction!!, bytes, !deferred)
        } catch (_: RuntimeException) { false }
        if (accepted) MoshTransferNotifications.clearPaused(context, id)
        changed()
        return accepted
    }

    fun started(id: String, direction: String, progress: (Map<*, *>) -> Unit, finish: () -> Unit): Long? {
        if (running.containsKey(id) || actions.snapshot().any { it.id == id && it.action == "cancel" }) return null
        val generation = execution.started(id)
        if (!publishGrant(id)) {
            execution.stopped(id, generation, "unavailable")
            changed()
            return null
        }
        val work = Running(generation, progress, finish)
        running[id] = work
        work.expiry = Runnable {
            if (running[id] === work) {
                stopped(id, generation, "unavailable")
                work.finish()
                MoshTransferNotifications.paused(context, id, direction)
            }
        }
        renew(work)
        MoshTransferNotifications.clearPaused(context, id)
        changed()
        return generation
    }

    fun stopped(id: String, generation: Long, reason: String): Boolean {
        if (!execution.stopped(id, generation, reason)) return false
        publishGrant(id)
        running.remove(id)?.expiry?.let(handler::removeCallbacks)
        changed()
        return true
    }

    fun work(values: Any?) {
        val facts = (values as? List<*>)?.map { it as Map<*, *> } ?: return
        val present = facts.mapNotNull { it["id"] as? String }.toSet()
        for ((id, work) in running.toMap()) {
            if (id !in present) { stopped(id, work.generation, "finished"); work.finish() }
        }
        for (value in facts) {
            val id = value["id"] as? String ?: continue
            val work = running[id] ?: continue
            if (value["state"] in QUIESCENT) {
                stopped(id, work.generation, "finished")
                work.finish()
            } else {
                val completed = MoshWaitingNotifications.integer(value["completedBytes"])
                if (completed > work.completed) { work.completed = completed; renew(work) }
                work.progress(value)
            }
        }
        if (Build.VERSION.SDK_INT < 34) recovery.retain(facts.filter { it["state"] !in QUIESCENT }
            .mapNotNull { it["id"] as? String }.toSet())
    }

    fun unavailable() {
        for ((id, work) in running.toMap()) {
            stopped(id, work.generation, "unavailable")
            work.finish()
        }
    }

    fun cancel(id: String) {
        try {
            actions.offer(id, "cancel")
            if (Build.VERSION.SDK_INT < 34) recovery.forget(id)
        }
        finally {
            val work = running[id]
            if (work != null) { stopped(id, work.generation, "userStopped"); work.finish() }
            jobs.cancel(id)
            MoshTransferNotifications.clearPaused(context, id)
        }
        actionsChanged()
    }

    fun accept(intent: Intent) {
        val id = MoshTransferIntents.id(intent) ?: return
        if (intent.action != MoshTransferIntents.RESUME) return
        actions.offer(id, "resume")
        actionsChanged()
    }

    fun takeActions() = actions.snapshot().map { mapOf("id" to it.id, "action" to it.action, "revision" to it.revision) }
    fun acknowledge(values: List<*>) {
        for (value in values) {
            val entry = value as Map<*, *>
            actions.acknowledge(entry["id"] as String, MoshWaitingNotifications.integer(entry["revision"]))
        }
    }

    fun snapshot() = mapOf("incarnation" to execution.incarnation, "revision" to execution.revision(),
        "grants" to execution.snapshot().map { mapOf("id" to it.id, "generation" to it.generation,
            "allowed" to it.allowed, "reason" to it.reason) })

    private fun publishGrant(id: String): Boolean {
        val grant = execution.snapshot().first { it.id == id }
        return try { MoshNative.setTransferExecution(execution.incarnation, id, grant.generation, grant.allowed) == 0 }
        catch (_: LinkageError) { false }
    }

    private fun renew(work: Running) {
        work.expiry?.let { handler.removeCallbacks(it); handler.postDelayed(it, 120_000) }
    }

    companion object {
        private val QUIESCENT = setOf("complete", "failed", "cancelled", "paused", "waitingReceiver")
    }
}
