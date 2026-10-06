import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Records the existing notification seam; a held show exposes cancellation races.
class RecordingCallNotifications implements FlutterLocalNotificationsPlugin {
  int showCalls = 0;
  int? lastId;
  String? lastTitle;
  String? lastBody;
  NotificationDetails? lastDetails;
  Completer<void>? pendingShow;
  final cancelled = <int>[];

  @override
  Future<void> show(
      {required int id,
      String? title,
      String? body,
      NotificationDetails? notificationDetails,
      String? payload}) async {
    showCalls++;
    lastId = id;
    lastTitle = title;
    lastBody = body;
    lastDetails = notificationDetails;
    await pendingShow?.future;
  }

  @override
  Future<void> cancel({required int id, String? tag}) async =>
      cancelled.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}
