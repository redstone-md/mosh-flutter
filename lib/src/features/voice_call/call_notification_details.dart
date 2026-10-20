import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// The call owner plays/stops the ringtone. A second notification sound can
// interrupt its audio focus, and the ordinary message channel must stay audible.
const callNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'mosh_incoming_calls',
    'Incoming calls',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.call,
    playSound: false,
    visibility: NotificationVisibility.private,
  ),
);
