package app.mosh.mosh;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;

/** Only opaque actions cross process death; native persistence must acknowledge them. */
public final class MoshTransferActions {
    public interface Store { String read(); void write(String value); }
    public static final class Entry {
        public final String id;
        public final String action;
        public final long revision;
        Entry(String id, String action, long revision) {
            this.id = id; this.action = action; this.revision = revision;
        }
    }
    private final Store store;
    private LinkedHashMap<String, Entry> entries;
    private long revision;

    public MoshTransferActions(Store store) {
        this.store = store;
        entries = new LinkedHashMap<>();
        for (String line : store.read().split("\n")) {
            if (line.isEmpty()) continue;
            String[] fields = line.split(" ");
            if (fields.length != 3) throw new IllegalStateException("Invalid transfer action journal");
            validate(fields[0], fields[1]);
            long version = Long.parseLong(fields[2]);
            if (version <= 0 || entries.size() >= 32) throw new IllegalStateException("Invalid action revision");
            entries.put(fields[0], new Entry(fields[0], fields[1], version));
            revision = Math.max(revision, version);
        }
    }

    public List<Entry> snapshot() { return new ArrayList<>(entries.values()); }

    public long offer(String id, String action) {
        validate(id, action);
        Entry previous = entries.get(id);
        if (previous != null && previous.action.equals(action)) return previous.revision;
        if (revision == Long.MAX_VALUE || previous == null && entries.size() >= 32)
            throw new IllegalStateException("Transfer action journal full");
        LinkedHashMap<String, Entry> next = new LinkedHashMap<>(entries);
        next.put(id, new Entry(id, action, revision + 1));
        commit(next);
        return ++revision;
    }

    public void acknowledge(String id, long expectedRevision) {
        Entry current = entries.get(id);
        if (current == null || current.revision != expectedRevision) return;
        LinkedHashMap<String, Entry> next = new LinkedHashMap<>(entries);
        next.remove(id);
        commit(next);
    }

    private void commit(LinkedHashMap<String, Entry> next) {
        StringBuilder value = new StringBuilder();
        for (Entry entry : next.values()) value.append(entry.id).append(' ')
            .append(entry.action).append(' ').append(entry.revision).append('\n');
        store.write(value.toString());
        entries = next;
    }

    private static void validate(String id, String action) {
        if (id == null || !id.matches("transfer-[0-9a-f]{32}") ||
                !"cancel".equals(action) && !"resume".equals(action))
            throw new IllegalArgumentException("Invalid opaque transfer action");
    }
}
