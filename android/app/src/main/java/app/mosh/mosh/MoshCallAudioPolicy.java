package app.mosh.mosh;

/** Android's selected communication output determines its microphone. */
final class MoshCallAudioPolicy {
    private static final String DEFAULT_INPUT = "android:communication-input";

    static String defaultInput(boolean sourcePresent) {
        return sourcePresent ? DEFAULT_INPUT : null;
    }

    static boolean acceptsInput(boolean sourcePresent, String requested) {
        return sourcePresent && (requested == null || DEFAULT_INPUT.equals(requested));
    }
}
