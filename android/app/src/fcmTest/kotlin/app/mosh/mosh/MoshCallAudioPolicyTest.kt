package app.mosh.mosh

import android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
import android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO
import android.media.AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
import android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
import android.media.AudioDeviceInfo.TYPE_TELEPHONY
import android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET
import org.junit.Assert.assertEquals
import org.junit.Test

// Android 8-11 has no communication devices, so the policy picks the outputs a
// call can reach there. This runs with the FCM build's JVM tests, the only
// local unit test source set the app has.
class MoshCallAudioPolicyTest {
    private fun outputs(vararg types: Int): List<Int> = MoshCallAudioPolicy.legacyOutputs(types.toList()) { it }

    @Test
    fun aBluetoothHeadsetIsOfferedOnceBesideTheSpeakerAndEarpiece() {
        assertEquals(
            listOf(TYPE_BUILTIN_EARPIECE, TYPE_BUILTIN_SPEAKER, TYPE_BLUETOOTH_SCO),
            outputs(TYPE_BUILTIN_EARPIECE, TYPE_BUILTIN_SPEAKER, TYPE_TELEPHONY,
                TYPE_BLUETOOTH_A2DP, TYPE_BLUETOOTH_SCO, TYPE_BLUETOOTH_SCO),
        )
    }

    @Test
    fun aWiredHeadsetTakesTheEarpiecesPlace() {
        assertEquals(
            listOf(TYPE_BUILTIN_SPEAKER, TYPE_WIRED_HEADSET),
            outputs(TYPE_BUILTIN_EARPIECE, TYPE_BUILTIN_SPEAKER, TYPE_WIRED_HEADSET),
        )
    }

    @Test
    fun eachOutputMapsToTheSwitchThatReachesIt() {
        assertEquals(MoshCallAudioPolicy.LegacyRoute.SPEAKER, MoshCallAudioPolicy.legacyRoute(TYPE_BUILTIN_SPEAKER))
        assertEquals(MoshCallAudioPolicy.LegacyRoute.BLUETOOTH, MoshCallAudioPolicy.legacyRoute(TYPE_BLUETOOTH_SCO))
        assertEquals(MoshCallAudioPolicy.LegacyRoute.HANDSET, MoshCallAudioPolicy.legacyRoute(TYPE_WIRED_HEADSET))
        assertEquals(MoshCallAudioPolicy.LegacyRoute.HANDSET, MoshCallAudioPolicy.legacyRoute(TYPE_BUILTIN_EARPIECE))
    }
}
