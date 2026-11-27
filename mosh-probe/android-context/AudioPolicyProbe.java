package app.mosh.mosh;

import java.util.List;

public final class AudioPolicyProbe {
    // android.media.AudioDeviceInfo values; this probe runs without the SDK.
    private static final int EARPIECE = 1, SPEAKER = 2, WIRED = 3, SCO = 7, USB = 22;

    public static void main(String[] args) {
        String input = MoshCallAudioPolicy.defaultInput(true);
        if (input == null || input.isBlank()) throw new AssertionError("detected microphone must reach the native inventory before permission");
        if (MoshCallAudioPolicy.defaultInput(false) != null) throw new AssertionError("no source must produce no microphone");
        if (!MoshCallAudioPolicy.acceptsInput(true, null)) throw new AssertionError("system route must accept its microphone");
        if (!MoshCallAudioPolicy.acceptsInput(true, input)) throw new AssertionError("default input alias must work");
        if (MoshCallAudioPolicy.acceptsInput(true, "other-mic")) throw new AssertionError("independent microphone selection is unsupported");
        if (MoshCallAudioPolicy.acceptsInput(false, null)) throw new AssertionError("missing microphone must fail selection");
        if (MoshCallAudioPolicy.acceptsInput(false, input)) throw new AssertionError("stale input must fail selection");
        List<Integer> plain = MoshCallAudioPolicy.legacyOutputs(List.of(EARPIECE, SPEAKER, SCO, SCO), type -> type);
        if (!plain.equals(List.of(EARPIECE, SPEAKER, SCO))) throw new AssertionError("legacy outputs offer one earpiece, the speaker and one headset: " + plain);
        List<Integer> wired = MoshCallAudioPolicy.legacyOutputs(List.of(EARPIECE, SPEAKER, USB, WIRED), type -> type);
        if (!wired.equals(List.of(SPEAKER, USB))) throw new AssertionError("a plugged-in headset replaces the earpiece: " + wired);
        if (MoshCallAudioPolicy.legacyRoute(SCO) != MoshCallAudioPolicy.LegacyRoute.BLUETOOTH) throw new AssertionError("SCO routes to Bluetooth");
        if (MoshCallAudioPolicy.legacyRoute(WIRED) != MoshCallAudioPolicy.LegacyRoute.HANDSET) throw new AssertionError("a wired headset is the handset route");
        System.out.println("Android communication microphone inventory and selection policy verified");
    }
}
