package app.mosh.mosh;

import java.util.Set;

/** Exercises the production restart boundary through a durable store, not an OS mock. */
public final class TransferRecoveryProbe {
    private static final String FIRST = "transfer-11111111111111111111111111111111";
    private static final String SECOND = "transfer-22222222222222222222222222222222";

    public static void main(String[] args) {
        Memory store = new Memory();
        MoshTransferRecovery recovery = new MoshTransferRecovery(store);
        require(recovery.admit(FIRST, "download"), "Explicit download refused");
        require(recovery.admit(SECOND, "upload"), "Explicit upload refused");
        recovery = new MoshTransferRecovery(store);
        require(recovery.snapshot().size() == 2, "Process reclaim lost admitted operations");
        require(recovery.snapshot().get(0).direction.equals("download"), "Recovery lost transfer direction");
        require(recovery.admit(FIRST, "download") && recovery.snapshot().size() == 2, "Restart duplicated operation");
        recovery.forget(FIRST);
        recovery = new MoshTransferRecovery(store);
        require(recovery.snapshot().size() == 1, "Cancellation replayed after restart");
        recovery.retain(Set.of());
        require(new MoshTransferRecovery(store).snapshot().isEmpty(), "Absent native work revived");
        recovery.forget(FIRST);
        recovery.retain(Set.of());
        checkBounds();
        checkStorageRefusal();
        checkMalformed();
        checkSystemStop();
        System.out.println("Android opaque transfer recovery and durable OS Stop verified");
    }

    private static void checkBounds() {
        Memory store = new Memory();
        MoshTransferRecovery recovery = new MoshTransferRecovery(store);
        for (int i = 0; i < 32; i++) require(recovery.admit(String.format("transfer-%032x", i), "download"), "Journal filled early");
        require(!recovery.admit(String.format("transfer-%032x", 32), "download"), "Journal unbounded");
        require(new MoshTransferRecovery(store).snapshot().size() == 32, "Full journal lost on reclaim");
        try { recovery.admit(FIRST, "file/private/path"); throw new AssertionError("Secret metadata accepted"); }
        catch (IllegalArgumentException expected) { /* Only an opaque operation and direction are permitted. */ }
        try { recovery.admit(String.format("transfer-%032x", 0), "upload"); throw new AssertionError("Direction changed"); }
        catch (IllegalArgumentException expected) { /* Native operation identity is immutable. */ }
    }

    private static void checkStorageRefusal() {
        Memory store = new Memory();
        MoshTransferRecovery recovery = new MoshTransferRecovery(store);
        store.refuse = true;
        try { recovery.admit(FIRST, "download"); throw new AssertionError("Undurable start accepted"); }
        catch (IllegalStateException expected) { require(recovery.snapshot().isEmpty(), "Failed start changed memory"); }
        store.refuse = false;
        recovery.admit(FIRST, "download");
        store.refuse = true;
        try { recovery.forget(FIRST); throw new AssertionError("Undurable removal accepted"); }
        catch (IllegalStateException expected) { require(recovery.snapshot().size() == 1, "Failed removal changed memory"); }
    }

    private static void checkMalformed() {
        for (String value : new String[] { "v2\n", "v1\nchat-name download\n", "v1\n" + FIRST + " other\n",
                "v1\n" + FIRST + " download\n" + FIRST + " download\n", "x".repeat(4097) }) {
            Memory store = new Memory(); store.value = value;
            try { new MoshTransferRecovery(store); throw new AssertionError("Malformed recovery admitted"); }
            catch (IllegalStateException expected) { /* Corruption fails closed. */ }
        }
    }

    private static void checkSystemStop() {
        StopStore store = new StopStore();
        require(!new MoshSystemStopPolicy(store).blocked(0), "Normal reclaim fabricated OS Stop");
        require(new MoshSystemStopPolicy(store).blocked(100), "Fresh OS Stop ignored");
        require(new MoshSystemStopPolicy(store).blocked(0), "Exit-history eviction cleared OS Stop");
        new MoshSystemStopPolicy(store).reopened(0);
        require(!new MoshSystemStopPolicy(store).blocked(0), "Real reopen retained OS Stop");
        require(!new MoshSystemStopPolicy(store).blocked(100), "Old OS Stop replayed after reopen");
        require(new MoshSystemStopPolicy(store).blocked(101), "Later OS Stop ignored");
        store.refuse = true;
        try { new MoshSystemStopPolicy(store).reopened(101); throw new AssertionError("Failed clear acknowledged"); }
        catch (IllegalStateException expected) { require(store.value.blocked, "Failed reopen cleared durable fence"); }
    }

    private static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private static final class Memory implements MoshTransferRecovery.Store {
        String value = ""; boolean refuse;
        public String read() { return value; }
        public void write(String value) {
            if (refuse) throw new IllegalStateException("Storage refused");
            this.value = value;
        }
    }
    private static final class StopStore implements MoshSystemStopPolicy.Store {
        MoshSystemStopPolicy.Record value = new MoshSystemStopPolicy.Record(0, false);
        boolean refuse;
        public MoshSystemStopPolicy.Record read() { return value; }
        public void write(MoshSystemStopPolicy.Record value) {
            if (refuse) throw new IllegalStateException("Storage refused");
            this.value = value;
        }
    }
}
