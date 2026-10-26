package app.mosh.mosh;

/** Fences asynchronous native work facts against a later lifecycle/user intent. */
public final class MoshWaitingExecution {
    private long revision;
    private boolean fresh;
    private String mode = "offline";
    private int calls;
    private int transfers;

    public long revision() { return revision; }
    public void changed() { revision++; fresh = false; }

    public boolean accept(long capturedRevision, String actualMode, int calls, int transfers) {
        if (capturedRevision != revision) return false;
        if (calls < 0 || transfers < 0) throw new IllegalArgumentException("Negative work count");
        if (!actualMode.equals("active") && !actualMode.equals("waiting") && !actualMode.equals("offline") &&
                !actualMode.equals("unsupported"))
            throw new IllegalArgumentException("Invalid execution mode");
        this.mode = actualMode;
        this.calls = calls;
        this.transfers = transfers;
        fresh = true;
        return true;
    }

    public boolean canRelease(boolean interactive) {
        return fresh && calls == 0 && transfers == 0 &&
                (mode.equals("offline") || interactive && mode.equals("active"));
    }
}
