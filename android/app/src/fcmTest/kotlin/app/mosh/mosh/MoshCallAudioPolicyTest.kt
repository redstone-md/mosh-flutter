package app.mosh.mosh

import android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
import android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO
import android.media.AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
import android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
import android.media.AudioDeviceInfo.TYPE_TELEPHONY
import android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Test

// Android 8-11 has no communication devices, so the policy picks the outputs a
// call can reach there. This runs with the FCM build's JVM tests, the only
// local unit test source set the app has.
class MoshCallAudioPolicyTest {
    private fun outputs(vararg types: Int): List<Int> = MoshCallAudioPolicy.legacyOutputs(types.toList()) { it }

    // Regression (CodeAnt PR #201): a saved output was Android's
    // per-connection device id, so a headset that reconnected lost the pick.
    @Test
    fun aHeadsetKeepsItsIdAcrossReconnectsAndRenames() {
        val headset = MoshCallAudioPolicy.routeId(TYPE_BLUETOOTH_SCO, "AA:BB:CC:DD:EE:FF", "Buds")
        assertEquals(headset, MoshCallAudioPolicy.routeId(TYPE_BLUETOOTH_SCO, "AA:BB:CC:DD:EE:FF", "Kitchen buds"))
        assertNotEquals(headset, MoshCallAudioPolicy.routeId(TYPE_BLUETOOTH_SCO, "11:22:33:44:55:66", "Buds"))
        // The id is saved and logged, so it does not spell out the address.
        assertFalse(headset.contains("EE:FF", ignoreCase = true))
    }

    @Test
    fun builtInRoutesWithoutAnAddressDifferByType() {
        assertNotEquals(
            MoshCallAudioPolicy.routeId(TYPE_BUILTIN_SPEAKER, "", "Pixel"),
            MoshCallAudioPolicy.routeId(TYPE_BUILTIN_EARPIECE, "", "Pixel"),
        )
    }

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
