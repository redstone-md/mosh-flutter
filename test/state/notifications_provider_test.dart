// Slice-3 voice-call: tests for the notificationsReadyProvider seam -- the
// Riverpod mirror of React's `notificationsReady()` ref-gate. The real
// init needs a platform plugin (flutter_local_notifications hosts), which
// is absent under `flutter test`, so these tests inject a recording fake
// via flutterLocalNotificationsPluginProvider (the seam convention -- same
// shape as gatewayProvider / voiceCaptureFactoryProvider overrides).
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/state/notifications_provider.dart';

/// A recording fake of the plugin: every override method returns a benign
/// value and `show` records (id, title, body) so a test can assert the gate
/// fired. `noSuchMethod` covers the rest so any unmocked call surfaces
/// loudly (the orchestrator-provider-test convention).
class _RecordingNotifications implements FlutterLocalNotificationsPlugin {
  int showCalls = 0;
  int? lastId;
  String? lastTitle;
  String? lastBody;
  InitializationSettings? initializationSettings;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializationSettings = settings;
    return true;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    showCalls++;
    lastId = id;
    lastTitle = title;
    lastBody = body;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}

/// A fake whose `initialize` returns false -- the init-failed branch
/// (notificationsReadyProvider resolves false; the in-app modal is the
/// signal regardless).
class _FailingInitNotifications implements FlutterLocalNotificationsPlugin {
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async =>
      false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}

class _NullInitNotifications implements FlutterLocalNotificationsPlugin {
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}

void main() {
  group('notificationsReadyProvider', () {
    test('resolves true when the plugin initializes successfully', () async {
      final container = ProviderContainer(overrides: [
        flutterLocalNotificationsPluginProvider
            .overrideWithValue(_RecordingNotifications()),
      ]);
      addTearDown(container.dispose);

      final ready = await container.read(notificationsReadyProvider.future);
      expect(ready, isTrue);
      // The sync read of the AsyncValue reflects the resolved data too.
      expect(container.read(notificationsReadyProvider).value, isTrue);
    });

    test('Android initialization requests granted notification permission',
        () async {
      final plugin = _RecordingNotifications();
      var requests = 0;
      final container = ProviderContainer(overrides: [
        flutterLocalNotificationsPluginProvider.overrideWithValue(plugin),
        notificationPlatformProvider
            .overrideWithValue(MoshNotificationPlatform.android),
        androidNotificationPermissionProvider.overrideWithValue((_) async {
          requests++;
          return true;
        }),
      ]);
      addTearDown(container.dispose);

      expect(await container.read(notificationsReadyProvider.future), isTrue);
      expect(requests, 1);
      expect(
        plugin.initializationSettings?.android?.defaultIcon,
        'ic_stat_mosh',
      );
      expect(
        File('android/app/src/main/res/drawable/ic_stat_mosh.xml').existsSync(),
        isTrue,
      );
    });

    for (final permission in <bool?>[false, null]) {
      test('Android permission $permission closes the notification gate',
          () async {
        final container = ProviderContainer(overrides: [
          flutterLocalNotificationsPluginProvider
              .overrideWithValue(_RecordingNotifications()),
          notificationPlatformProvider
              .overrideWithValue(MoshNotificationPlatform.android),
          androidNotificationPermissionProvider
              .overrideWithValue((_) async => permission),
        ]);
        addTearDown(container.dispose);

        expect(await container.read(notificationsReadyProvider.future), isFalse);
      });
    }

    test('Windows host keeps the existing ready behavior', () async {
      final plugin = _RecordingNotifications();
      final container = ProviderContainer(overrides: [
        flutterLocalNotificationsPluginProvider.overrideWithValue(plugin),
      ]);
      addTearDown(container.dispose);

      expect(await container.read(notificationsReadyProvider.future), isTrue);
      expect(plugin.initializationSettings?.windows, isNotNull);
    });

    test('resolves false when the plugin init returns false', () async {
      final container = ProviderContainer(overrides: [
        flutterLocalNotificationsPluginProvider
            .overrideWithValue(_FailingInitNotifications()),
      ]);
      addTearDown(container.dispose);

      final ready = await container.read(notificationsReadyProvider.future);
      expect(ready, isFalse);
    });

    test('resolves false when the plugin init returns null', () async {
      final container = ProviderContainer(overrides: [
        flutterLocalNotificationsPluginProvider
            .overrideWithValue(_NullInitNotifications()),
      ]);
      addTearDown(container.dispose);

      expect(await container.read(notificationsReadyProvider.future), isFalse);
    });

    test(
        'a consumer reads the gate via ref.watch(.value) and asserts the '
        'override behaviour', () async {
      // The voice-call layer's gate is `ref.read(notificationsReadyProvider)
      // .value ?? false`. Verify that override plumbing works: with a
      // passing fake the gate is open, with a failing fake it is closed.
      final passing = ProviderContainer(overrides: [
        flutterLocalNotificationsPluginProvider
            .overrideWithValue(_RecordingNotifications()),
      ]);
      addTearDown(passing.dispose);
      await passing.read(notificationsReadyProvider.future);
      expect(passing.read(notificationsReadyProvider).value ?? false, isTrue);

      final failing = ProviderContainer(overrides: [
        flutterLocalNotificationsPluginProvider
            .overrideWithValue(_FailingInitNotifications()),
      ]);
      addTearDown(failing.dispose);
      await failing.read(notificationsReadyProvider.future);
      expect(failing.read(notificationsReadyProvider).value ?? false, isFalse);
    });
  });
}
