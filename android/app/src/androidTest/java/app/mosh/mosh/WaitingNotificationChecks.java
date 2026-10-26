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
            require(notification(manager).actions == null || notification(manager).actions.length == 0,
                "Message created an unscoped action");
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
            checkCallStyle(context, policy);
            checkTransfers(context);
            checkFullPreview(manager, policy, publisher);
        } finally {
            manager.cancel(TAG, 2);
        }
    }

    private static void checkFullPreview(NotificationManager manager, MoshWaitingPolicy policy,
            MoshWaitingNotifications publisher) {
        String text = TEXT.repeat(80);
        Map<String, Object> value = message(3);
        value.put("text", text);
        policy.notificationPolicy(false, true);
        require("posted".equals(publisher.publish(value)), "Full preview publication failed");
        Notification preview = notification(manager);
        require(text.contentEquals(preview.extras.getCharSequence(Notification.EXTRA_TEXT)),
            "Explicit preview truncated message text");
        require(text.contentEquals(preview.extras.getCharSequence(Notification.EXTRA_BIG_TEXT)),
            "Expanded preview lost full message text");
        policy.notificationPolicy(false, false);
        publisher.refreshPrivacy();
        hidden(notification(manager), true, true);
    }

    private static void checkTransfers(Context context) {
        String id = "transfer-11111111111111111111111111111111";
        Notification progress = MoshTransferNotifications.INSTANCE.build(context, id, "download", 2, 10, false);
        require(progress.extras.getInt(Notification.EXTRA_PROGRESS) == 20, "Real byte progress lost");
        require(progress.contentIntent != null && progress.actions.length == 1, "Transfer actions missing");
        require(context.getPackageName().equals(progress.actions[0].actionIntent.getCreatorPackage()),
            "Foreign transfer action");
        if (android.os.Build.VERSION.SDK_INT >= 31)
            require(progress.actions[0].actionIntent.isImmutable(), "Mutable transfer action");
        hidden(progress, true, true);
        Notification paused = MoshTransferNotifications.INSTANCE.build(context, id, "upload", 0, 0, true);
        require((paused.flags & Notification.FLAG_ONGOING_EVENT) == 0, "Paused transfer claims ongoing execution");
        android.content.Intent resume = new android.content.Intent().setAction(MoshTransferIntents.RESUME)
            .setData(android.net.Uri.parse("mosh-transfer://resume/" + id))
            .putExtra(MoshTransferIntents.ID, id);
        require(id.equals(MoshTransferIntents.INSTANCE.id(resume)), "Opaque transfer action lost");
        require(MoshTransferIntents.INSTANCE.forFlutter(resume).getData() == null,
            "Transfer action replaced the Flutter route");
        require(MoshTransferIntents.INSTANCE.id(new android.content.Intent()
            .putExtra(MoshTransferIntents.ID, "/private/file")) == null, "Transfer accepts a file path as ID");
    }

    private static void checkCallStyle(Context context, MoshWaitingPolicy policy) {
        Map<String, Object> value = message(3);
        value.put("phase", "incoming");
        value.put("answerCapability", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        value.put("declineCapability", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        MoshCallNotificationBuilder builder = new MoshCallNotificationBuilder(context, policy, () -> false);
        Notification call = builder.build(value, 20_000);
        hidden(call, true, true);
        require(call.visibility == Notification.VISIBILITY_PRIVATE, "System lock race can disclose caller");
        require(call.actions != null && call.actions.length >= 2, "CallStyle has no Answer/Decline");
        require(call.publicVersion != null && call.publicVersion.actions != null &&
            call.publicVersion.actions.length >= 2, "Generic lockscreen call lost its actions");
        for (Notification.Action action : call.actions) {
            require(context.getPackageName().equals(action.actionIntent.getCreatorPackage()), "Foreign call action");
            if (android.os.Build.VERSION.SDK_INT >= 31)
                require(action.actionIntent.isImmutable(), "Mutable call PendingIntent");
        }
        require(MoshCallIntents.INSTANCE.capability(new android.content.Intent()
            .putExtra("callId", "known-call")) == null, "Launcher accepted raw call ID");
        android.content.Intent action = new android.content.Intent().setAction(MoshCallIntents.ANSWER)
            .setData(android.net.Uri.parse("mosh-call://action/opaque"));
        require(MoshCallIntents.INSTANCE.forFlutter(action).getData() == null, "Call action replaced the Flutter route");
        android.content.Intent link = new android.content.Intent(android.content.Intent.ACTION_VIEW,
            android.net.Uri.parse("mosh://join/invite"));
        require(MoshCallIntents.INSTANCE.forFlutter(link).getData().equals(link.getData()), "Ordinary invite link lost");
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
            hiddenField(value.extras.get(key), name, text);
        }
        require(value.tickerText == null, "Protected notification has a ticker");
        if (value.publicVersion != null) hidden(value.publicVersion, true, true);
    }

    private static void hiddenField(Object value, boolean name, boolean text) {
        if (value instanceof android.os.Bundle) {
            android.os.Bundle bundle = (android.os.Bundle) value;
            for (String key : bundle.keySet()) hiddenField(bundle.get(key), name, text);
        } else if (value instanceof Iterable<?>) {
            for (Object field : (Iterable<?>) value) hiddenField(field, name, text);
        } else if (value instanceof Object[]) {
            for (Object field : (Object[]) value) hiddenField(field, name, text);
        } else {
            if (android.os.Build.VERSION.SDK_INT >= 28 && value instanceof android.app.Person)
                value = ((android.app.Person) value).getName();
            String field = String.valueOf(value);
            require(!name || !field.contains(NAME), "Protected sender leaked through OS extras");
            require(!text || !field.contains(TEXT), "Protected message leaked through OS extras");
        }
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
