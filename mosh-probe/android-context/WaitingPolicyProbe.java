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
        System.out.println("Android waiting intent, disclosure and consent verified");
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
