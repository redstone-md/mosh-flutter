package app.mosh.mosh;

import android.app.Notification;
import android.app.NotificationManager;
import android.content.Context;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/** Actual OS publication, including privacy reduction between durable intake and notify. */
final class WaitingNotificationChecks {
    private static final String ID = "background-11111111111111111111111111111111";
    private static final String TAG = "mosh.delivery." + ID;
    private static final String NAME = "PRIVATE_SENDER_PROBE";
    private static final String TEXT = "PRIVATE_TEXT_PROBE";

    static void run(Context context) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        require(manager.areNotificationsEnabled(), "Grant POST_NOTIFICATIONS to the isolated test app first");
        MoshWaitingPolicy policy = new MoshWaitingPolicy(new Memory());
        AtomicBoolean unlocked = new AtomicBoolean(true);
        MoshWaitingNotifications publisher = new MoshWaitingNotifications(context, policy, unlocked::get);
        try {
            // Content was eligible when received, but the native app lock closes before publication.
            Map<String, Object> pending = message(1);
            unlocked.set(false);
            require("posted".equals(publisher.publish(pending)), "OS refused protected publication");
            hidden(notification(manager), true, true);
            policy.notificationPolicy(false, true);
            require("posted".equals(publisher.publish(message(2))), "Explicit text publication failed");
            Notification preview = notification(manager);
            hidden(preview, true, false);
            require(TEXT.contentEquals(preview.extras.getCharSequence(Notification.EXTRA_TEXT)), "Text consent ignored");
            require("posted".equals(publisher.publish(message(1))), "Stale replay failed");
            require(notification(manager).extras.getLong("mosh.deliveryRevision") == 2,
                "Old durable revision overwrote newer OS notification");
            policy.notificationPolicy(false, false);
            publisher.refreshPrivacy();
            hidden(notification(manager), true, true);
        } finally {
            manager.cancel(TAG, 2);
        }
    }

    private static Map<String, Object> message(int revision) {
        Map<String, Object> value = new HashMap<>();
        value.put("kind", "message");
        value.put("id", ID);
        value.put("revision", revision);
        value.put("messageCount", 1);
        value.put("sender", NAME);
        value.put("text", TEXT);
        return value;
    }

    private static Notification notification(NotificationManager manager) {
        for (android.service.notification.StatusBarNotification entry : manager.getActiveNotifications()) {
            if (TAG.equals(entry.getTag()) && entry.getId() == 2) return entry.getNotification();
        }
        throw new AssertionError("Published OS notification missing");
    }

    private static void hidden(Notification value, boolean name, boolean text) {
        for (String key : value.extras.keySet()) {
            String field = String.valueOf(value.extras.get(key));
            require(!name || !field.contains(NAME), "Protected sender leaked through OS extras");
            require(!text || !field.contains(TEXT), "Protected message leaked through OS extras");
        }
        require(value.tickerText == null, "Protected notification has a ticker");
        require(value.actions == null || value.actions.length == 0, "Message created an unscoped action");
        if (value.publicVersion != null) hidden(value.publicVersion, true, true);
    }

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static final class Memory implements MoshWaitingPolicy.Store {
        private MoshWaitingPolicy.Record record;
        public MoshWaitingPolicy.Record read() { return record; }
        public void write(MoshWaitingPolicy.Record value) { record = value; }
    }
}
