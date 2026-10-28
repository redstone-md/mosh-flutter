package app.mosh.mosh;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.function.LongSupplier;

/** Bounded ephemeral intent intake; only the native encrypted ledger authorizes an action. */
public final class MoshCallActions {
    public static final class Entry {
        public final String capability;
        public final boolean interactiveAnswer;
        private final long queuedAt;
        Entry(String capability, boolean answer, long now) {
            this.capability = capability;
            interactiveAnswer = answer;
            queuedAt = now;
        }
    }

    private final LongSupplier clock;
    private final LinkedHashMap<String, Entry> pending = new LinkedHashMap<>();

    public MoshCallActions(LongSupplier clock) { this.clock = clock; }

    public boolean offer(String capability, boolean answer) {
        if (capability == null || !capability.matches("[0-9a-f]{64}")) return false;
        expire();
        Entry previous = pending.get(capability);
        if (previous != null) {
            if (answer && !previous.interactiveAnswer)
                pending.put(capability, new Entry(capability, true, previous.queuedAt));
            return true;
        }
        if (pending.size() >= 16) return false;
        pending.put(capability, new Entry(capability, answer, clock.getAsLong()));
        return true;
    }

    public List<Entry> take() {
        expire();
        List<Entry> values = new ArrayList<>(pending.values());
        pending.clear();
        return values;
    }

    private void expire() {
        long now = clock.getAsLong();
        pending.values().removeIf(value -> now - value.queuedAt > 120_000 || now < value.queuedAt);
    }
}
