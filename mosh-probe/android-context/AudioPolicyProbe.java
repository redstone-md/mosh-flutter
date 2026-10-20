package app.mosh.mosh;

public final class AudioPolicyProbe {
    public static void main(String[] args) {
        String input = MoshCallAudioPolicy.defaultInput(true);
        if (input == null || input.isBlank()) throw new AssertionError("detected microphone must reach the native inventory before permission");
        if (MoshCallAudioPolicy.defaultInput(false) != null) throw new AssertionError("no source must produce no microphone");
        if (!MoshCallAudioPolicy.acceptsInput(true, null)) throw new AssertionError("system route must accept its microphone");
        if (!MoshCallAudioPolicy.acceptsInput(true, input)) throw new AssertionError("default input alias must work");
        if (MoshCallAudioPolicy.acceptsInput(true, "other-mic")) throw new AssertionError("independent microphone selection is unsupported");
        if (MoshCallAudioPolicy.acceptsInput(false, null)) throw new AssertionError("missing microphone must fail selection");
        if (MoshCallAudioPolicy.acceptsInput(false, input)) throw new AssertionError("stale input must fail selection");
        System.out.println("Android communication microphone inventory and selection policy verified");
    }
}
