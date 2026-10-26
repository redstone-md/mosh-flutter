package app.mosh.mosh;

import java.util.Objects;

/** One elapsed-time grant, independent of notification, media and wall clocks. */
public final class MoshAccessPolicy {
    public interface Store {
        Record read();
        void write(Record value);
    }
    public interface Clock {
        long elapsed();
        Integer boot();
    }
    public static final class Record {
        public final int delaySeconds;
        public final Integer bootCount;
        public final Long deadlineElapsedMs;
        public final String state;
        public Record(int delay, Integer boot, Long deadline, String state) {
            if (!validDelay(delay)) throw new IllegalArgumentException("Invalid lock delay");
            if (!state.equals("locked") && !state.equals("interactive") && !state.equals("grace")) {
                throw new IllegalArgumentException("Invalid access state");
            }
            this.delaySeconds = delay;
            this.bootCount = boot;
            this.deadlineElapsedMs = deadline;
            this.state = state;
        }
    }

    private final Store store;
    private final Clock clock;
    private Record record;
    private long lastElapsed;

    public MoshAccessPolicy(Store store, Clock clock) {
        this.store = store;
        this.clock = clock;
        Record saved = store.read();
        record = saved == null ? new Record(60, clock.boot(), null, "locked") : saved;
        lastElapsed = clock.elapsed();
        // Interactive is a process-local grant. Only a verified grace record
        // can survive process reclamation, never a former foreground marker.
        if (!record.state.equals("grace") || !validGrace()) lockInMemory();
    }

    public synchronized Record snapshot() {
        validateClock();
        if (record.state.equals("grace") && !validGrace()) commit(locked());
        return record;
    }

    public synchronized boolean allowed() {
        return !snapshot().state.equals("locked");
    }

    public synchronized void authenticated() {
        commit(new Record(record.delaySeconds, clock.boot(), null, "interactive"));
        lastElapsed = clock.elapsed();
    }

    public synchronized void interactive() {
        if (allowed()) authenticated();
    }

    public synchronized void saveUiState(int seconds, String state, boolean foreground) {
        validateUiState(state, foreground);
        setDelay(seconds);
        applyUiState(state, foreground);
    }

    /** UI state is not authentication, even if a delayed save says interactive. */
    public synchronized void applyUiState(String state, boolean foreground) {
        validateUiState(state, foreground);
        if (state.equals("interactive")) interactive();
        else if (state.equals("grace")) departed();
    }

    private void validateUiState(String state, boolean foreground) {
        switch (state) {
            case "interactive":
                if (!foreground) throw new IllegalStateException("Not foreground");
                break;
            case "locked":
                if (allowed()) throw new IllegalStateException("Access remains allowed");
                break;
            case "grace": break;
            default: throw new IllegalArgumentException("Invalid access state");
        }
    }

    public synchronized void departed() {
        if (!allowed() || record.state.equals("grace")) return;
        long now = clock.elapsed();
        long duration = record.delaySeconds * 1_000L;
        if (duration == 0 || now < 0 || now > Long.MAX_VALUE - duration || clock.boot() == null) {
            commit(locked());
        } else {
            commit(new Record(record.delaySeconds, clock.boot(), now + duration, "grace"));
        }
    }

    public synchronized void setDelay(int seconds) {
        if (!validDelay(seconds)) throw new IllegalArgumentException("Invalid lock delay");
        Record current = snapshot();
        commit(new Record(seconds, current.bootCount, current.deadlineElapsedMs, current.state));
        snapshot();
    }

    private void validateClock() {
        long now = clock.elapsed();
        if (now < 0 || now < lastElapsed || !Objects.equals(record.bootCount, clock.boot())) {
            commit(locked());
        }
        lastElapsed = now;
    }

    private boolean validGrace() {
        Long deadline = record.deadlineElapsedMs;
        long now = clock.elapsed();
        return record.bootCount != null && Objects.equals(record.bootCount, clock.boot()) &&
            now >= 0 && deadline != null && deadline > now &&
            deadline - now <= record.delaySeconds * 1_000L;
    }

    private Record locked() {
        return new Record(record.delaySeconds, clock.boot(), null, "locked");
    }

    private void lockInMemory() { record = locked(); }

    private void commit(Record next) {
        try {
            store.write(next);
            record = next;
        } catch (RuntimeException error) {
            lockInMemory();
            throw error;
        }
    }

    public static boolean validDelay(int seconds) {
        return seconds == 0 || seconds == 60 || seconds == 300 || seconds == 600 || seconds == 1800;
    }
}
