package app.mosh.mosh;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Set;

/** OS restart hints only; the encrypted native journal still admits every byte. */
public final class MoshTransferRecovery {
    public interface Store { String read(); void write(String value); }
    public static final class Entry {
        public final String id;
        public final String direction;
        Entry(String id, String direction) { this.id = id; this.direction = direction; }
    }
    private final Store store;
    private LinkedHashMap<String, Entry> entries = new LinkedHashMap<>();

    public MoshTransferRecovery(Store store) {
        this.store = store;
        String saved = store.read();
        if (saved.isEmpty()) return;
        if (saved.length() > 4096 || !saved.startsWith("v1\n"))
            throw new IllegalStateException("Invalid recovery journal");
        for (String line : saved.substring(3).split("\n")) {
            if (line.isEmpty()) continue;
            String[] fields = line.split(" ");
            if (fields.length != 2 || entries.size() >= 32 || entries.containsKey(fields[0]))
                throw new IllegalStateException("Invalid recovery entry");
            try { validate(fields[0], fields[1]); }
            catch (IllegalArgumentException error) { throw new IllegalStateException("Invalid recovery entry"); }
            entries.put(fields[0], new Entry(fields[0], fields[1]));
        }
    }

    public List<Entry> snapshot() { return new ArrayList<>(entries.values()); }

    public boolean admit(String id, String direction) {
        validate(id, direction);
        Entry existing = entries.get(id);
        if (existing != null) {
            if (!existing.direction.equals(direction)) throw new IllegalArgumentException("Transfer direction changed");
            return true;
        }
        if (entries.size() >= 32) return false;
        LinkedHashMap<String, Entry> next = new LinkedHashMap<>(entries);
        next.put(id, new Entry(id, direction));
        commit(next);
        return true;
    }

    public void forget(String id) {
        if (!entries.containsKey(id)) return;
        LinkedHashMap<String, Entry> next = new LinkedHashMap<>(entries);
        next.remove(id);
        commit(next);
    }

    /** Only a fresh native work snapshot may retire absent or quiescent work. */
    public void retain(Set<String> current) {
        LinkedHashMap<String, Entry> next = new LinkedHashMap<>(entries);
        if (next.keySet().retainAll(current)) commit(next);
    }

    private void commit(LinkedHashMap<String, Entry> next) {
        StringBuilder value = new StringBuilder("v1\n");
        for (Entry entry : next.values()) value.append(entry.id).append(' ').append(entry.direction).append('\n');
        store.write(value.toString());
        entries = next;
    }

    private static void validate(String id, String direction) {
        if (id == null || !id.matches("transfer-[0-9a-f]{32}") ||
                !"upload".equals(direction) && !"download".equals(direction))
            throw new IllegalArgumentException("Invalid opaque recovery intent");
    }
}
