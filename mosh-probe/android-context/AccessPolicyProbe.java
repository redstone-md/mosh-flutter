package app.mosh.mosh;

/** Exercises the production elapsed-time policy at its clock/storage boundary. */
public final class AccessPolicyProbe {
    public static void main(String[] args) {
        Memory store = new Memory();
        Clock clock = new Clock();
        MoshAccessPolicy policy = new MoshAccessPolicy(store, clock);
        require(!policy.allowed(), "Cold interactive access must start locked");
        policy.authenticated();
        clock.now = 1_000;
        policy.departed();
        clock.now = 30_000;
        policy.departed(); // A later screen-off must keep the first deadline.
        require(policy.snapshot().deadlineElapsedMs == 61_000, "Screen off extended grace");
        clock.now = 60_999;
        require(policy.allowed(), "Grace ended before its exact deadline");
        clock.now = 61_000;
        require(!policy.allowed(), "Late resume exposed expired chats");
        checkDelays(clock);
        checkRestartFences(clock);
        checkStorageFailure(clock);
        checkExternalDeparture(clock);
        checkRejectedSave(clock);
        System.out.println("Android app-lock deadline verified");
    }

    private static void checkDelays(Clock clock) {
        for (int delay : new int[] {0, 60, 300, 600, 1800}) {
            clock.now = 1_000;
            MoshAccessPolicy policy = new MoshAccessPolicy(new Memory(), clock);
            policy.setDelay(delay);
            policy.authenticated();
            policy.departed();
            require(policy.allowed() == (delay != 0), "Wrong immediate/delayed policy");
            clock.now += delay * 1_000L;
            require(!policy.allowed(), "A supported delay did not expire");
        }
    }

    private static void checkRestartFences(Clock clock) {
        Memory store = new Memory();
        clock.now = 1_000;
        MoshAccessPolicy policy = new MoshAccessPolicy(store, clock);
        policy.authenticated();
        require(!new MoshAccessPolicy(store, clock).allowed(), "Cold interactive grant reused");
        policy.departed();
        require(new MoshAccessPolicy(store, clock).allowed(), "Same-boot grace was lost");
        clock.boot++;
        require(!new MoshAccessPolicy(store, clock).allowed(), "Previous boot granted access");
        clock.boot = null;
        require(!new MoshAccessPolicy(store, clock).allowed(), "Unknown boot granted access");
        clock.boot = 5;
        store.record = new MoshAccessPolicy.Record(60, 5, 500_000L, "grace");
        require(!new MoshAccessPolicy(store, clock).allowed(), "Future-invalid grant reused");
        policy = new MoshAccessPolicy(new Memory(), clock);
        policy.authenticated();
        clock.now--;
        require(!policy.allowed(), "Elapsed clock rollback granted access");
    }

    private static void checkStorageFailure(Clock clock) {
        Memory store = new Memory();
        clock.now = 1_000;
        MoshAccessPolicy policy = new MoshAccessPolicy(store, clock);
        policy.authenticated();
        store.fail = true;
        try {
            policy.departed();
            throw new AssertionError("Refused persistence reported success");
        } catch (IllegalStateException expected) {
            require(!policy.allowed(), "Refused persistence left chat access granted");
        }
    }

    private static void checkExternalDeparture(Clock clock) {
        clock.now = 1_000;
        MoshAccessPolicy policy = new MoshAccessPolicy(new Memory(), clock);
        policy.authenticated();
        policy.departed(); // A document picker stops the protected Activity.
        clock.now = 30_000;
        policy.departed(); // Home from the picker cannot renew the first absence.
        require(policy.snapshot().deadlineElapsedMs == 61_000, "Picker extended grace");
        clock.now = 61_000;
        policy.applyUiState("interactive", true); // An old frame/settings save arrives.
        require(!policy.allowed(), "A stale foreground save unlocked expired chats");
        policy.authenticated();
        policy.departed();
        clock.now++;
        policy.applyUiState("interactive", true);
        require(policy.allowed() && policy.snapshot().state.equals("interactive"),
            "Returning before the bounded absence lost valid access");
    }

    private static void checkRejectedSave(Clock clock) {
        clock.now = 1_000;
        Memory store = new Memory();
        MoshAccessPolicy policy = new MoshAccessPolicy(store, clock);
        policy.authenticated();
        for (String state : new String[] {"interactive", "locked", "invalid"}) {
            int writes = store.writes;
            try {
                policy.saveUiState(300, state, false);
                throw new AssertionError("Invalid UI save reported success");
            } catch (IllegalStateException | IllegalArgumentException expected) {
                require(policy.snapshot().delaySeconds == 60, "Rejected save changed lock delay");
                require(store.writes == writes, "Rejected save wrote preferences");
            }
        }
        policy.saveUiState(300, "grace", false);
        require(policy.snapshot().delaySeconds == 300 &&
            policy.snapshot().deadlineElapsedMs == 301_000, "Valid delay/state save failed");
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static final class Memory implements MoshAccessPolicy.Store {
        MoshAccessPolicy.Record record;
        boolean fail;
        int writes;
        @Override public MoshAccessPolicy.Record read() { return record; }
        @Override public void write(MoshAccessPolicy.Record value) {
            if (fail) throw new IllegalStateException("Refused persistence");
            record = value;
            writes++;
        }
    }

    private static final class Clock implements MoshAccessPolicy.Clock {
        long now;
        Integer boot = 5;
        @Override public long elapsed() { return now; }
        @Override public Integer boot() { return boot; }
    }
}
