package app.mosh.mosh;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.List;
import java.util.function.ToIntFunction;

/** Android's selected communication output determines its microphone. */
final class MoshCallAudioPolicy {
    private static final String DEFAULT_INPUT = "android:communication-input";
    /** Enough to tell one phone's routes apart, too little to name the hardware. */
    private static final int ROUTE_HASH_BYTES = 6;

    // android.media.AudioDeviceInfo types, inlined by javac anyway, so this
    // policy compiles and runs under a plain JVM (android-context-check).
    private static final int TYPE_BUILTIN_EARPIECE = 1;
    private static final int TYPE_BUILTIN_SPEAKER = 2;
    private static final int TYPE_WIRED_HEADSET = 3;
    private static final int TYPE_WIRED_HEADPHONES = 4;
    private static final int TYPE_BLUETOOTH_SCO = 7;
    private static final int TYPE_USB_HEADSET = 22;

    /** The switch that reaches an output before Android 12's communication devices. */
    enum LegacyRoute { SPEAKER, BLUETOOTH, HANDSET }

    static String defaultInput(boolean sourcePresent) {
        return sourcePresent ? DEFAULT_INPUT : null;
    }

    static boolean acceptsInput(boolean sourcePresent, String requested) {
        return sourcePresent && (requested == null || DEFAULT_INPUT.equals(requested));
    }

    /**
     * The id an output keeps while it is reconnected, so a saved pick finds it
     * in a later call: its kind and its hardware address, or its product name
     * when it has no address (built-in routes, Android 8.x). Android's own
     * device id is handed out again on every connection. The identity is
     * hashed: the id is saved with the settings and can reach a call's log
     * line, which has no business carrying a hardware address.
     */
    static String routeId(int type, String address, CharSequence productName) {
        String identity = address == null || address.isEmpty() ? String.valueOf(productName) : address;
        byte[] digest;
        try {
            digest = MessageDigest.getInstance("SHA-256").digest(identity.getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException missing) {
            throw new IllegalStateException("Every Java platform provides SHA-256", missing);
        }
        StringBuilder id = new StringBuilder("android:").append(type).append(':');
        for (int i = 0; i < ROUTE_HASH_BYTES; i++) id.append(String.format("%02x", digest[i]));
        return id.toString();
    }

    /**
     * The outputs a call can choose on Android 8-11: the speaker, one Bluetooth
     * headset and one handset route. With the speaker and Bluetooth off Android
     * plays to a plugged-in wired headset, else the earpiece, so only that one
     * of the two is offered.
     */
    static <T> List<T> legacyOutputs(List<T> outputs, ToIntFunction<T> type) {
        boolean wired = outputs.stream().anyMatch(output -> isWired(type.applyAsInt(output)));
        List<T> choices = new ArrayList<>();
        boolean bluetooth = false;
        boolean handset = false;
        for (T output : outputs) {
            int kind = type.applyAsInt(output);
            if (kind == TYPE_BUILTIN_SPEAKER) {
                choices.add(output);
            } else if (kind == TYPE_BLUETOOTH_SCO && !bluetooth) {
                bluetooth = true;
                choices.add(output);
            } else if (!handset && (wired ? isWired(kind) : kind == TYPE_BUILTIN_EARPIECE)) {
                handset = true;
                choices.add(output);
            }
        }
        return choices;
    }

    static LegacyRoute legacyRoute(int type) {
        if (type == TYPE_BUILTIN_SPEAKER) return LegacyRoute.SPEAKER;
        if (type == TYPE_BLUETOOTH_SCO) return LegacyRoute.BLUETOOTH;
        return LegacyRoute.HANDSET;
    }

    private static boolean isWired(int type) {
        return type == TYPE_WIRED_HEADSET
            || type == TYPE_WIRED_HEADPHONES
            || type == TYPE_USB_HEADSET;
    }
}
