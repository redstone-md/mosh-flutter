package app.mosh.mosh

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Retained-engine owner for access state; key operations are added by IVO-135. */
internal class MoshAccess(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "app.mosh.mosh/access")
    private val state by lazy { MoshAccessState(context) }
    private val authentication = MoshChatAuthentication(context)
    private val shield = MoshAccessShield()
    private val handler = Handler(Looper.getMainLooper())
    private val expiry = Runnable { publish() }
    private var activity: MainActivity? = null
    private var resumed = false
    private var revision = 0L
    private val foreground get() = resumed && context.getSystemService(PowerManager::class.java).isInteractive &&
        !context.getSystemService(KeyguardManager::class.java).isDeviceLocked

    init {
        channel.setMethodCallHandler(::dispatch)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == Intent.ACTION_USER_PRESENT) {
                    protect()
                    publish()
                    return
                }
                if (intent.action != Intent.ACTION_SCREEN_OFF) return
                authentication.cancel()
                protect()
                update { state.policy.departed() }
            }
        }
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF).apply { addAction(Intent.ACTION_USER_PRESENT) }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else context.registerReceiver(receiver, filter)
    }

    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "readAccessState" -> result.success(snapshot())
                "saveAccessState" -> {
                    state.save(call.arguments as Map<*, *>, foreground)
                    publish()
                    result.success(snapshot())
                }
                "authenticateChats" -> authenticate(call, result)
                "protectedFrameReady" -> {
                    val generation = call.argument<Number>("generation")?.toLong()
                    val visible = call.argument<Boolean>("chatsVisible") == true
                    if (generation == shield.generation) {
                        if (!visible || state.policy.allowed()) shield.ready(generation)
                        else { protect(); publish() }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            protect()
            publishFailure()
            result.error("ACCESS_STATE_UNAVAILABLE", "Access state unavailable", null)
        }
    }

    private fun authenticate(call: MethodCall, result: MethodChannel.Result) {
        val reason = call.argument<String>("reason")?.takeIf { it.isNotBlank() && it.length <= 240 }
            ?: error("Missing authentication reason")
        authentication.authenticate(reason) { outcome ->
            if (outcome == "authenticated" && foreground) {
                try {
                    state.policy.authenticated()
                    publish()
                    result.success(outcome)
                } catch (_: Exception) {
                    result.error("ACCESS_STATE_UNAVAILABLE", "Access state unavailable", null)
                }
            } else result.success(if (outcome == "authenticated") "canceled" else outcome)
        }
    }

    fun attach(activity: MainActivity) {
        this.activity = activity
        authentication.attach(activity)
        shield.attach(activity)
    }

    fun detach(activity: MainActivity) {
        if (this.activity !== activity) return
        authentication.detach(activity)
        shield.detach(activity)
        this.activity = null
        resumed = false
    }

    fun resumed() {
        resumed = true
        protect()
        authentication.resumed()
        publish()
    }

    fun paused() { resumed = false; authentication.paused(); publish() }

    fun stopped() {
        // Device-credential confirmation can stop this Activity on both API
        // branches. Home, screen-off and detach fence/cancel the request instead.
        if (activity?.isChangingConfigurations == true || authentication.showing) return
        // A picker can hide this Activity and then launch Home without another
        // callback here. Bound that absence by the same ordinary grace period.
        protect()
        update { state.policy.departed() }
    }

    fun leaving() {
        if (authentication.credentialShowing) return
        authentication.cancel()
        protect()
        update { state.policy.departed() }
    }

    fun result(request: Int, code: Int) {
        authentication.result(request, code)
    }

    private fun protect() { shield.protect() }

    private fun update(action: () -> Unit) {
        try { action(); publish() } catch (_: Exception) { publishFailure() }
    }

    private fun snapshot(): Map<String, Any?> = state.snapshot() + mapOf(
        "revision" to ++revision, "shieldGeneration" to shield.generation, "deviceInteractive" to foreground)

    private fun publish() {
        try {
            val value = snapshot()
            channel.invokeMethod("accessStateChanged", value)
            handler.removeCallbacks(expiry)
            val deadline = value["deadlineElapsedMs"] as? Long
            if (value["state"] == "grace" && deadline != null) {
                handler.postDelayed(expiry, (deadline - SystemClock.elapsedRealtime()).coerceAtLeast(1))
            }
        } catch (_: Exception) { publishFailure() }
    }

    private fun publishFailure() {
        channel.invokeMethod("accessStateChanged", mapOf("error" to true, "revision" to ++revision,
            "shieldGeneration" to shield.generation))
    }
}
