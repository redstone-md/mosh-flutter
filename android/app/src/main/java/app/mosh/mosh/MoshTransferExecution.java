package app.mosh.mosh;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.UUID;

/** Memory-only OS authority; a scheduled job never fabricates an execution grant. */
public final class MoshTransferExecution {
    public static final class Grant {
        public final String id;
        public final long generation;
        public final boolean allowed;
        public final String reason;
        Grant(String id, long generation, boolean allowed, String reason) {
            this.id = id;
            this.generation = generation;
            this.allowed = allowed;
            this.reason = reason;
        }
    }

    public final String incarnation = UUID.randomUUID().toString().replace("-", "");
    private final LinkedHashMap<String, Grant> grants = new LinkedHashMap<>();
    private long revision;

    public long revision() { return revision; }
    public List<Grant> snapshot() { return new ArrayList<>(grants.values()); }

    public void scheduled(String id) {
        validate(id);
        if (!grants.containsKey(id)) update(id, false, "unavailable");
    }

    public long started(String id) {
        validate(id);
        return update(id, true, "running");
    }

    public boolean stopped(String id, long generation, String reason) {
        Grant current = grants.get(id);
        if (current == null || current.generation != generation) return false;
        if (!reason.equals("constraints") && !reason.equals("finished") &&
                !reason.equals("userStopped") && !reason.equals("unavailable"))
            throw new IllegalArgumentException("Invalid stop reason");
        update(id, false, reason);
        return true;
    }

    private long update(String id, boolean allowed, String reason) {
        if (revision == Long.MAX_VALUE) throw new IllegalStateException("OS grant revision exhausted");
        grants.put(id, new Grant(id, ++revision, allowed, reason));
        trim();
        return revision;
    }

    private void trim() {
        if (grants.size() <= 64) return;
        java.util.Iterator<Grant> values = grants.values().iterator();
        while (values.hasNext() && grants.size() > 64) {
            if (!values.next().allowed) values.remove();
        }
    }

    private static void validate(String id) {
        if (id == null || !id.matches("transfer-[0-9a-f]{32}"))
            throw new IllegalArgumentException("Invalid opaque transfer id");
    }
}
