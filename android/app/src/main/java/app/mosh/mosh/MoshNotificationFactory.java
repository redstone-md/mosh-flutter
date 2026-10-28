package app.mosh.mosh;

import android.app.Notification;
import android.app.NotificationManager;
import android.content.Context;
import com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin;
import com.dexterous.flutterlocalnotifications.models.NotificationDetails;
import com.dexterous.flutterlocalnotifications.models.NotificationStyle;
import com.dexterous.flutterlocalnotifications.models.styles.BigTextStyleInformation;

/** Uses the installed plugin's builder without registering another plugin/channel. */
final class MoshNotificationFactory extends FlutterLocalNotificationsPlugin {
    static Notification message(Context context, String title, String body, int count, boolean alert) {
        NotificationDetails details = new NotificationDetails();
        details.id = 2;
        details.title = title;
        details.body = body;
        details.icon = "ic_stat_mosh";
        details.channelId = "mosh_notifications";
        details.channelName = context.getString(R.string.mosh_notification_channel);
        details.importance = NotificationManager.IMPORTANCE_HIGH;
        details.priority = 1;
        details.style = NotificationStyle.BigText;
        details.styleInformation = new BigTextStyleInformation(false, false,
            body, false, null, false, null, false);
        details.autoCancel = true;
        details.onlyAlertOnce = !alert;
        details.silent = !alert;
        details.playSound = true;
        details.enableVibration = true;
        details.number = count;
        details.visibility = 0;
        return createNotification(context, details);
    }
}
