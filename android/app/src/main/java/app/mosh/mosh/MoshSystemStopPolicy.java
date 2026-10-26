package app.mosh.mosh;

/** A user stop survives eviction from Android's bounded process-exit history. */
public final class MoshSystemStopPolicy {
    public interface Store { Record read(); void write(Record record); }
    public static final class Record {
        public final long acknowledgedExit;
        public final boolean blocked;
        public Record(long acknowledgedExit, boolean blocked) {
            this.acknowledgedExit = acknowledgedExit; this.blocked = blocked;
        }
    }
    private final Store store;
    public MoshSystemStopPolicy(Store store) { this.store = store; }
    public boolean blocked(long latestExit) {
        Record record = store.read();
        if (record.blocked) return true;
        if (latestExit <= record.acknowledgedExit) return false;
        store.write(new Record(latestExit, true));
        return true;
    }
    public void reopened(long latestExit) {
        store.write(new Record(Math.max(store.read().acknowledgedExit, latestExit), false));
    }
}
