package app.mosh.mosh

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioFocusRequest
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** The call owns playback; async preparation may never resurrect a stopped ring. */
internal class MoshRingtone(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "app.mosh/call-ringtone")
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var id: Int? = null
    private var focus: AudioFocusRequest? = null
    private val timeout = Runnable { stop() }

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> start(requireNotNull(call.argument<Int>("id")),
                        requireNotNull(call.argument<String>("kind")))
                    "stop" -> if (call.argument<Int>("id") == id) stop()
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(null)
            } catch (error: Exception) {
                stop()
                result.error("ringtone_failed", error.javaClass.simpleName, null)
            }
        }
    }

    private fun start(token: Int, kind: String) {
        require(kind == "incoming" || kind == "outgoing")
        stop()
        val manager = context.getSystemService(AudioManager::class.java)
        // A custom recording must still obey Android silent/vibrate settings.
        if (kind == "incoming" && manager.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        val next = MediaPlayer()
        player = next
        id = token
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
        handler.postDelayed(timeout, 30_000)
    }

    private fun requestFocus(attributes: AudioAttributes, token: Int): Boolean {
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
