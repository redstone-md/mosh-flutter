package app.mosh.mosh;

/** Exercises user intent at the production preference boundary, without an OS mock. */
public final class WaitingPolicyProbe {
    public static void main(String[] args) {
        Memory store = new Memory();
        MoshWaitingPolicy policy = new MoshWaitingPolicy(store);
        require(!policy.shouldWait(), "Waiting started before setup");
        policy.enable();
        require(policy.shouldWait(), "Completed setup did not enable waiting");
        policy.stop();
        require(!policy.shouldWait(), "Stop did not release idle waiting");
        policy = new MoshWaitingPolicy(store);
        require(!policy.snapshot().waitingEnabled, "Process restart forgot Stop");
        require(!policy.shouldWait(), "Restart reenabled waiting");
        require(policy.offerBatteryExemption(), "First exemption offer missing");
        require(!policy.offerBatteryExemption(), "Exemption offer repeated");
        require(!new MoshWaitingPolicy(store).offerBatteryExemption(), "Restart repeated exemption offer");
        checkPrivacy(policy);
        checkRefusal(store);
        checkDrainFence();
        checkActions();
        checkTransferGrants();
        checkTransferActions();
        System.out.println("Android waiting intent, disclosure and consent verified");
    }

    private static void checkTransferActions() {
        final String[] saved = { "" };
        MoshTransferActions.Store store = new MoshTransferActions.Store() {
            public String read() { return saved[0]; }
            public void write(String value) { saved[0] = value; }
        };
        String id = "transfer-11111111111111111111111111111111";
        MoshTransferActions actions = new MoshTransferActions(store);
        long first = actions.offer(id, "cancel");
        actions = new MoshTransferActions(store);
        require(actions.snapshot().size() == 1, "Restart lost unacknowledged cancellation");
        long newer = actions.offer(id, "resume");
        actions.acknowledge(id, first);
        require(actions.snapshot().get(0).revision == newer, "Old acknowledgement erased newer action");
        require(actions.snapshot().get(0).action.equals("resume"), "Action replacement lost");
        actions.acknowledge(id, newer);
        require(new MoshTransferActions(store).snapshot().isEmpty(), "Acknowledged action replayed");
        MoshTransferActions refused = new MoshTransferActions(new MoshTransferActions.Store() {
            public String read() { return ""; }
            public void write(String value) { throw new IllegalStateException("Refused"); }
        });
        try { refused.offer(id, "cancel"); throw new AssertionError("Undurable action accepted"); }
        catch (IllegalStateException expected) {
            require(refused.snapshot().isEmpty(), "Refused action mutated memory");
        }
    }

    private static void checkTransferGrants() {
        MoshTransferExecution execution = new MoshTransferExecution();
        String id = "transfer-11111111111111111111111111111111";
        execution.scheduled(id);
        require(!execution.snapshot().get(0).allowed, "Scheduling fabricated a running OS job");
        long first = execution.started(id);
        require(execution.snapshot().get(0).allowed, "Actual OS start did not grant execution");
        execution.stopped(id, first, "constraints");
        require(!execution.snapshot().get(0).allowed, "OS stop retained execution grant");
        long second = execution.started(id);
        require(!execution.stopped(id, first, "finished"), "Old invocation stopped replacement job");
        require(execution.snapshot().get(0).allowed, "Stale stop removed actual grant");
        execution.stopped(id, second, "finished");
        require(!execution.snapshot().get(0).allowed, "Finished job retained grant");
        require(!execution.incarnation.equals(new MoshTransferExecution().incarnation), "Process incarnation reused");
    }

    private static void checkActions() {
        java.util.concurrent.atomic.AtomicLong clock = new java.util.concurrent.atomic.AtomicLong();
        MoshCallActions actions = new MoshCallActions(clock::get);
        require(!actions.offer("known-call-id", true), "Raw call ID accepted as capability");
        String capability = "a".repeat(64);
        require(actions.offer(capability, true), "Valid intent lost before cold owner attached");
        require(actions.offer(capability, true), "Repeated PendingIntent rejected instead of coalesced");
        require(actions.take().size() == 1, "Repeated intent created duplicate actions");
        require(actions.take().isEmpty(), "Action drain replayed consumed intent");
        actions.offer(capability, false);
        actions.offer(capability, true);
        require(actions.take().get(0).interactiveAnswer, "Presentation swallowed a racing explicit Answer");
        for (int i = 0; i < 16; i++) require(actions.offer(String.format("%064x", i), false), "Queue filled early");
        require(!actions.offer("b".repeat(64), false), "Intent queue unbounded");
        clock.set(120_001);
        require(actions.take().isEmpty(), "Obsolete queued intent survived bounded initialization");
        require(actions.offer(capability, true), "Expired queue did not release capacity");
        require(actions.take().get(0).interactiveAnswer, "Activity Answer lost its presentation intent");
    }

    private static void checkDrainFence() {
        MoshWaitingExecution execution = new MoshWaitingExecution();
        long beforeStop = execution.revision();
        execution.changed();
        require(!execution.accept(beforeStop, "offline", 0, 0), "Stale facts crossed Stop");
        require(!execution.canRelease(false), "Stop released before fresh native facts");
        require(execution.accept(execution.revision(), "active", 1, 0), "Fresh call refused");
        require(!execution.canRelease(false), "Stop terminated admitted call");
        execution.accept(execution.revision(), "active", 0, 1);
        require(!execution.canRelease(true), "Foreground lost admitted transfer");
        execution.accept(execution.revision(), "active", 0, 0);
        require(!execution.canRelease(false), "Background active node lost service");
        require(execution.canRelease(true), "Foreground could not own active node");
        execution.changed();
        require(!execution.canRelease(true), "Lifecycle change reused old work facts");
        execution.accept(execution.revision(), "offline", 0, 0);
        require(execution.canRelease(false), "Drained native owner retained service");
    }

    private static void checkPrivacy(MoshWaitingPolicy policy) {
        require(!policy.namesAllowed(false, false), "Locked names visible by default");
        require(!policy.textAllowed(true, true), "System-locked text visible by default");
        require(policy.textAllowed(true, false), "Unlocked disclosure unexpectedly denied");
        policy.notificationPolicy(false, true);
        require(!policy.namesAllowed(false, true), "Text consent disclosed caller names");
        require(policy.textAllowed(false, true), "Explicit locked text consent lost");
    }

    private static void checkRefusal(Memory store) {
        MoshWaitingPolicy policy = new MoshWaitingPolicy(store);
        store.fail = true;
        try {
            policy.enable();
            throw new AssertionError("Refused durable preference returned success");
        } catch (IllegalStateException expected) {
            require(!policy.snapshot().waitingEnabled, "Failed preference enabled background work");
        }
    }

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static final class Memory implements MoshWaitingPolicy.Store {
        MoshWaitingPolicy.Record value;
        boolean fail;
        public MoshWaitingPolicy.Record read() { return value; }
        public void write(MoshWaitingPolicy.Record value) {
            if (fail) throw new IllegalStateException("Refused");
            this.value = value;
        }
    }
}
