package app.mosh.mosh

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/** Android communication routes select the speaker and matching microphone. */
internal class MoshCallAudio(context: Context) {
    private val manager = context.getSystemService(AudioManager::class.java)
    private var active = false
    private var previousMode = AudioManager.MODE_NORMAL
    private var previousSpeaker = false
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        .setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
        .setOnAudioFocusChangeListener { }
        .build()

    @Synchronized
    fun devices(): JSONObject {
        val outputs = JSONArray()
        for (device in routes()) {
            outputs.put(JSONObject().put("id", "android:${device.id}")
                .put("name", when (device.type) {
                    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Speaker"
                    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Earpiece"
                    else -> device.productName.toString()
                }))
        }
        return JSONObject().put("inputs", JSONArray()).put("outputs", outputs)
    }

    private fun routes(): List<AudioDeviceInfo> = if (Build.VERSION.SDK_INT >= 31) {
        manager.availableCommunicationDevices
    } else {
        manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).filter {
            it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER ||
                it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
        }
    }

    @Synchronized
    fun select(value: JSONObject): JSONObject {
        if (!active) {
            previousMode = manager.mode
            @Suppress("DEPRECATION")
            previousSpeaker = manager.isSpeakerphoneOn
            check(manager.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
            manager.mode = AudioManager.MODE_IN_COMMUNICATION
            active = true
        }
        val id = value.optString("output").takeUnless { it.isBlank() || it == "null" }
        val device = routes().firstOrNull { "android:${it.id}" == id }
        val ok = when {
            Build.VERSION.SDK_INT >= 31 && device != null -> manager.setCommunicationDevice(device)
            Build.VERSION.SDK_INT >= 31 -> { manager.clearCommunicationDevice(); id == null }
            device != null -> {
                @Suppress("DEPRECATION")
                manager.isSpeakerphoneOn = device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                true
            }
            else -> {
                @Suppress("DEPRECATION")
                manager.isSpeakerphoneOn = false
                id == null
            }
        }
        return JSONObject().put("input_ok", true).put("output_ok", ok)
    }

    @Synchronized
    fun stop() {
        if (!active) return
        if (Build.VERSION.SDK_INT >= 31) manager.clearCommunicationDevice()
        else {
            @Suppress("DEPRECATION")
            manager.isSpeakerphoneOn = previousSpeaker
        }
        manager.mode = previousMode
        manager.abandonAudioFocusRequest(focus)
        active = false
    }
}
