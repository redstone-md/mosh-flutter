package app.mosh.mosh;

import android.media.AudioDeviceInfo;
import java.util.ArrayList;
import java.util.List;
import java.util.function.ToIntFunction;

/** Android's selected communication output determines its microphone. */
final class MoshCallAudioPolicy {
    private static final String DEFAULT_INPUT = "android:communication-input";

    /** The switch that reaches an output before Android 12's communication devices. */
    enum LegacyRoute { SPEAKER, BLUETOOTH, HANDSET }

    static String defaultInput(boolean sourcePresent) {
        return sourcePresent ? DEFAULT_INPUT : null;
    }

    static boolean acceptsInput(boolean sourcePresent, String requested) {
        return sourcePresent && (requested == null || DEFAULT_INPUT.equals(requested));
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
            if (kind == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
                choices.add(output);
            } else if (kind == AudioDeviceInfo.TYPE_BLUETOOTH_SCO && !bluetooth) {
                bluetooth = true;
                choices.add(output);
            } else if (!handset && (wired ? isWired(kind) : kind == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)) {
                handset = true;
                choices.add(output);
            }
        }
        return choices;
    }

    static LegacyRoute legacyRoute(int type) {
        if (type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) return LegacyRoute.SPEAKER;
        if (type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) return LegacyRoute.BLUETOOTH;
        return LegacyRoute.HANDSET;
    }

    private static boolean isWired(int type) {
        return type == AudioDeviceInfo.TYPE_WIRED_HEADSET
            || type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
            || type == AudioDeviceInfo.TYPE_USB_HEADSET;
    }
}
