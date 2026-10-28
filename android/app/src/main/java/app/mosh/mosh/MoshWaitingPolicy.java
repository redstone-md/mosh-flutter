package app.mosh.mosh;

/** Durable user choices; execution facts and permission grants remain external. */
public final class MoshWaitingPolicy {
    public interface Store {
        Record read();
        void write(Record value);
    }

    public static final class Record {
        public final boolean setupComplete;
        public final boolean waitingEnabled;
        public final boolean batteryExemptionOffered;
        public final boolean showNamesWhenLocked;
        public final boolean showTextWhenLocked;

        public Record(boolean setup, boolean enabled, boolean offered, boolean names, boolean text) {
            setupComplete = setup;
            waitingEnabled = enabled;
            batteryExemptionOffered = offered;
            showNamesWhenLocked = names;
            showTextWhenLocked = text;
        }
    }

    private final Store store;
    private Record record;
    private boolean unavailable;

    public MoshWaitingPolicy(Store store) {
        this.store = store;
        try {
            record = store.read();
            if (record == null) record = new Record(false, true, false, false, false);
        } catch (RuntimeException error) {
            record = new Record(false, false, false, false, false);
            unavailable = true;
        }
    }

    public synchronized Record snapshot() { return record; }
    public synchronized boolean storageUnavailable() { return unavailable; }

    public synchronized void enable() {
        commit(new Record(true, true, record.batteryExemptionOffered,
                record.showNamesWhenLocked, record.showTextWhenLocked));
    }

    /** Acknowledgement follows durable off intent, before presentation changes. */
    public synchronized void stop() {
        commit(new Record(record.setupComplete, false, record.batteryExemptionOffered,
                record.showNamesWhenLocked, record.showTextWhenLocked));
    }

    public synchronized boolean offerBatteryExemption() {
        if (record.batteryExemptionOffered) return false;
        commit(new Record(record.setupComplete, record.waitingEnabled, true,
                record.showNamesWhenLocked, record.showTextWhenLocked));
        return true;
    }

    public synchronized void notificationPolicy(boolean names, boolean text) {
        commit(new Record(record.setupComplete, record.waitingEnabled,
                record.batteryExemptionOffered, names, text));
    }

    public synchronized boolean shouldWait() { return record.setupComplete && record.waitingEnabled; }

    public synchronized boolean namesAllowed(boolean accessAllowed, boolean deviceLocked) {
        return accessAllowed && !deviceLocked || record.showNamesWhenLocked;
    }

    public synchronized boolean textAllowed(boolean accessAllowed, boolean deviceLocked) {
        return accessAllowed && !deviceLocked || record.showTextWhenLocked;
    }

    private void commit(Record next) {
        try {
            store.write(next);
            record = next;
            unavailable = false;
        } catch (RuntimeException error) {
            record = new Record(record.setupComplete, false, record.batteryExemptionOffered,
                    false, false);
            unavailable = true;
            throw error;
        }
    }
}
