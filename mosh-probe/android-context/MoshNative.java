package app.mosh.mosh;

import java.lang.ref.WeakReference;

/** The same JNI entry point as the Android Activity; no Android framework stub. */
public final class MoshNative {
    private static native void initialize(Object application);
    private static native boolean contextReady();

    public static void main(String[] args) throws Exception {
        System.load(args[0]);
        if (args.length > 1 && args[1].equals("without-bootstrap")) {
            if (!contextReady()) throw new AssertionError("native audio context is missing");
            return;
        }
        try {
            initialize(null);
            throw new AssertionError("a missing application must be refused");
        } catch (RuntimeException expected) {
            // A failed initialization must still permit the real application.
        }
        Object application = new Object();
        WeakReference<Object> reference = new WeakReference<>(application);
        initialize(application);
        initialize(application); // Activity recreation must not initialize twice.
        application = null;
        for (int i = 0; i < 3; i++) {
            System.gc();
            Thread.sleep(10);
        }
        if (!contextReady()) throw new AssertionError("native audio context is missing");
        if (reference.get() == null) throw new AssertionError("application reference was released");
        System.out.println("JNI bootstrap, Activity recreation and application lifetime verified");
    }
}
