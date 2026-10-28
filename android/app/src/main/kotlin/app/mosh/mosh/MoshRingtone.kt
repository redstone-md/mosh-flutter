package app.mosh.mosh

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioFocusRequest
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.os.Vibrator
import android.os.VibrationEffect
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** The call owns playback; async preparation may never resurrect a stopped ring. */
internal class MoshRingtone(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "app.mosh/call-ringtone")
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var id: String? = null
    private var focus: AudioFocusRequest? = null
    private val vibration by lazy { context.getSystemService(Vibrator::class.java) }
    private val timeout = Runnable { stop() }

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> start("dart:${requireNotNull(call.argument<Int>("id"))}",
                        requireNotNull(call.argument<String>("kind")))
                    "stop" -> if ("dart:${call.argument<Int>("id")}" == id) stop()
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(null)
            } catch (error: Exception) {
                stop()
                result.error("ringtone_failed", error.javaClass.simpleName, null)
            }
        }
    }

    fun incoming(key: String, remainingMs: Long) {
        if (id == "background:$key") return
        start("background:$key", "incoming", remainingMs.coerceIn(1, 30_000))
    }

    fun stopIncoming(key: String) { if (id == "background:$key") stop() }

    private fun start(token: String, kind: String, durationMs: Long = 30_000) {
        require(kind == "incoming" || kind == "outgoing")
        stop()
        val manager = context.getSystemService(AudioManager::class.java)
        if (kind == "incoming" && manager.ringerMode == AudioManager.RINGER_MODE_SILENT) return
        id = token
        if (kind == "incoming" && manager.ringerMode == AudioManager.RINGER_MODE_VIBRATE) {
            vibrate(durationMs)
            return
        }
        val next = MediaPlayer()
        next.setWakeMode(context, android.os.PowerManager.PARTIAL_WAKE_LOCK)
        player = next
        val usage = if (kind == "incoming") AudioAttributes.USAGE_NOTIFICATION_RINGTONE
            else AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING
        val attributes = AudioAttributes.Builder().setUsage(usage)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        next.setAudioAttributes(attributes)
        if (!requestFocus(attributes, token)) {
            stop()
            return
        }
        val asset = FlutterInjector.instance().flutterLoader()
            .getLookupKeyForAsset("assets/audio/ringtone_$kind.wav")
        context.assets.openFd(asset).use { next.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
        next.isLooping = true
        next.setOnPreparedListener {
            if (player === it && id == token) {
                try { it.start() } catch (_: IllegalStateException) { stop() }
            }
        }
        next.setOnErrorListener { failed, what, extra ->
            Log.w("MoshRingtone", "Playback failed: $what/$extra")
            if (player === failed) stop()
            true
        }
        next.prepareAsync()
        handler.postDelayed(timeout, durationMs)
    }

    private fun vibrate(durationMs: Long) {
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build()
        val pattern = mutableListOf(0L)
        var remaining = durationMs
        var pulse = true
        while (remaining > 0) {
            val interval = minOf(remaining, if (pulse) 500L else 1_000L)
            pattern.add(interval)
            remaining -= interval
            pulse = !pulse
        }
        // Hardware stops at the original deadline even if Android defers our Handler.
        vibration.vibrate(VibrationEffect.createWaveform(pattern.toLongArray(), -1), attributes)
        handler.postDelayed(timeout, durationMs)
    }

    private fun requestFocus(attributes: AudioAttributes, token: String): Boolean {
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener { change ->
                if (change < 0 && id == token) stop()
            }.build()
        focus = request
        return context.getSystemService(AudioManager::class.java).requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun stop() {
        handler.removeCallbacks(timeout)
        vibration.cancel()
        val old = player
        player = null
        id = null
        old?.release()
        focus?.let { context.getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }
        focus = null
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        stop()
    }
}
