package app.mosh.mosh;

import android.app.Instrumentation;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.View;
import android.view.ViewGroup;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.StandardMethodCodec;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Real channel/native-surface check; no Dart frame acknowledgment after expiry. */
public final class AccessExpiryChecks {
    public static void run(Instrumentation test, MainActivity activity) throws Exception {
        Context context = test.getTargetContext();
        require(context.getPackageName().endsWith(".linked_dm_test"), "Use the disposable test app");
        SharedPreferences preferences = context.getSharedPreferences("app.mosh.access.v1", Context.MODE_PRIVATE);
        Map<String, ?> original = preferences.getAll();
        AtomicReference<MoshAccess> owner = new AtomicReference<>();
        AtomicReference<Channel> observed = new AtomicReference<>();
        try {
            int boot = Settings.Global.getInt(context.getContentResolver(), Settings.Global.BOOT_COUNT);
            require(preferences.edit().clear().putInt("version", 1).putInt("delaySeconds", 60)
                .putInt("bootCount", boot).putString("state", "grace")
                .putLong("deadlineElapsedMs", SystemClock.elapsedRealtime() + 1500).commit(),
                "Could not prepare grace fixture");
            test.runOnMainSync(() -> {
                Channel channel = new Channel(activity);
                observed.set(channel);
                MoshAccess access = new MoshAccess(context, channel);
                owner.set(access);
                access.attach(activity);
                access.resumed();
            });
            Channel channel = observed.get();
            require(channel.expired.await(10, TimeUnit.SECONDS), "No expired-grace publication");
            if (channel.failure.get() != null) throw new AssertionError(channel.failure.get());
        } finally {
            if (owner.get() != null) test.runOnMainSync(() -> owner.get().detach(activity));
            restore(preferences, original);
        }
    }

    private static final class Channel implements BinaryMessenger {
        private final ViewGroup content;
        private final Set<View> originalViews = new HashSet<>();
        private final CountDownLatch expired = new CountDownLatch(1);
        private final AtomicReference<Throwable> failure = new AtomicReference<>();
        private BinaryMessageHandler handler;
        private long visibleGeneration;

        Channel(MainActivity activity) {
            content = activity.findViewById(android.R.id.content);
            for (int i = 0; i < content.getChildCount(); i++) originalViews.add(content.getChildAt(i));
        }

        @Override public void setMessageHandler(String name, BinaryMessageHandler value) { handler = value; }
        @Override public void send(String name, ByteBuffer message) { send(name, message, null); }
        @Override public void send(String name, ByteBuffer message, BinaryReply reply) {
            try {
                MethodCall event = StandardMethodCodec.INSTANCE.decodeMethodCall(readable(message));
                if (!event.method.equals("accessStateChanged")) return;
                Map<?, ?> state = (Map<?, ?>) event.arguments;
                long generation = ((Number) state.get("shieldGeneration")).longValue();
                if ("grace".equals(state.get("state"))) {
                    visibleGeneration = generation;
                    Map<String, Object> ready = new HashMap<>();
                    ready.put("generation", generation);
                    ready.put("chatsVisible", true);
                    handler.onMessage(readable(StandardMethodCodec.INSTANCE.encodeMethodCall(
                        new MethodCall("protectedFrameReady", ready))), ignored -> { });
                    require(!covered(), "Valid grace could not reveal the acknowledged frame");
                } else if ("locked".equals(state.get("state"))) {
                    require(visibleGeneration > 0, "Grace was not valid at startup");
                    require(generation > visibleGeneration, "Expiry reused the visible frame generation");
                    require(covered(), "Locked state was published before the native surface was covered");
                    expired.countDown();
                }
            } catch (Throwable error) { failure.set(error); expired.countDown(); }
        }

        private boolean covered() {
            for (int i = 0; i < content.getChildCount(); i++) {
                View view = content.getChildAt(i);
                if (!originalViews.contains(view) && view.getBackground() instanceof ColorDrawable &&
                    ((ColorDrawable) view.getBackground()).getColor() == Color.BLACK) return true;
            }
            return false;
        }
    }

    private static ByteBuffer readable(ByteBuffer encoded) {
        ByteBuffer value = encoded.duplicate();
        value.flip();
        return value;
    }

    private static void restore(SharedPreferences preferences, Map<String, ?> original) {
        SharedPreferences.Editor edit = preferences.edit().clear();
        for (Map.Entry<String, ?> entry : original.entrySet()) {
            Object value = entry.getValue();
            if (value instanceof Integer) edit.putInt(entry.getKey(), (Integer) value);
            else if (value instanceof Long) edit.putLong(entry.getKey(), (Long) value);
            else if (value instanceof String) edit.putString(entry.getKey(), (String) value);
            else throw new AssertionError("Unexpected access preference type");
        }
        require(edit.commit(), "Could not restore access preferences");
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
