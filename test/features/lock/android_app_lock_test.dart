import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';
import 'package:mosh/src/features/lock/android_app_lock_gate.dart';
import 'package:mosh/src/features/lock/android_app_lock_frame.dart';
import 'package:mosh/src/features/lock/app_lock_route_observer.dart';
import 'package:mosh/src/features/settings/app_lock_settings_card.dart';
import '../../support/pump.dart';

void main() {
  testWidgets(
      'canceled authentication keeps chats covered; unlock preserves drafts',
      (tester) async {
    var allowed = false;
    var outcome = 'canceled';
    var revision = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel, (call) async {
      if (call.method == 'authenticateChats') {
        allowed = outcome == 'authenticated';
        return outcome;
      }
      return _snapshot(allowed: allowed, revision: ++revision);
    });
    final access = AndroidAppAccess();
    await access.initialize();
    addTearDown(() {
      access.dispose();
      messenger.setMockMethodCallHandler(AndroidAppAccess.channel, null);
    });
    await pumpScreen(
        tester, const AndroidAppLockGate(child: Scaffold(body: TextField())),
        overrides: [androidAppAccessProvider.overrideWithValue(access)]);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    outcome = 'authenticated';
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsent draft');
    allowed = false;
    await _event(tester, _snapshot(allowed: false, revision: ++revision));
    await tester.pumpAndSettle();
    expect(find.text('unsent draft'), findsNothing);
    outcome = 'authenticated';
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('unsent draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'expired access removes protected dialogs and retains call dialogs',
      (tester) async {
    var revision = 0;
    messenger(tester).setMockMethodCallHandler(AndroidAppAccess.channel,
        (_) async => _snapshot(allowed: true, revision: ++revision));
    final access = AndroidAppAccess();
    await access.initialize();
    late BuildContext home;
    await pumpScreen(
        tester,
        AndroidAppLockFrame(
            access: access,
            child: AndroidAppLockGate(child: Builder(builder: (context) {
              home = context;
              return const Scaffold(body: Text('chat'));
            }))),
        observers: [appLockRouteObserver],
        overrides: [androidAppAccessProvider.overrideWithValue(access)]);
    unawaited(showDialog<void>(
        context: home,
        builder: (_) =>
            const AlertDialog(content: Text('protected attachment'))));
    await tester.pumpAndSettle();
    expect(find.text('protected attachment'), findsOneWidget);
    await _event(tester, _snapshot(allowed: false, revision: ++revision));
    await tester.pumpAndSettle();
    expect(find.text('protected attachment'), findsNothing);
    expect(find.text('chat'), findsNothing);
    unawaited(showDialog<void>(
        context: home,
        builder: (_) =>
            const AlertDialog(content: Text('late protected dialog'))));
    await tester.pump();
    expect(find.text('late protected dialog'), findsNothing,
        reason: 'a pending protected action must not paint above the lock');
    unawaited(showDialog<void>(
        context: home,
        routeSettings: const RouteSettings(name: callAccessRoute),
        builder: (_) => const AlertDialog(content: Text('call devices'))));
    await tester.pumpAndSettle();
    expect(find.text('call devices'), findsOneWidget);
    Navigator.of(home, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    access.dispose();
    messenger(tester).setMockMethodCallHandler(AndroidAppAccess.channel, null);
    appLockRouteObserver.setLocked(false);
  });

  testWidgets('the saved auto-lock setting offers exactly the approved delays',
      (tester) async {
    var revision = 0;
    var delay = 60;
    messenger(tester).setMockMethodCallHandler(AndroidAppAccess.channel,
        (call) async {
      if (call.method == 'saveAccessState') {
        delay = (call.arguments as Map)['delaySeconds'] as int;
      }
      return {
        ..._snapshot(allowed: true, revision: ++revision),
        'delaySeconds': delay
      };
    });
    final access = AndroidAppAccess();
    await access.initialize();
    await pumpScreen(tester, const Scaffold(body: AppLockSettingsCard()),
        overrides: [androidAppAccessProvider.overrideWithValue(access)]);
    expect(find.text('1 min'), findsOneWidget);
    await tester.tap(find.text('1 min'));
    await tester.pumpAndSettle();
    for (final label in ['Immediately', '1 min', '5 min', '10 min', '30 min']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('5 min'));
    await tester.pumpAndSettle();
    expect(delay, 300);
    expect(find.text('5 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    access.dispose();
    messenger(tester).setMockMethodCallHandler(AndroidAppAccess.channel, null);
  });
}

TestDefaultBinaryMessenger messenger(WidgetTester tester) =>
    tester.binding.defaultBinaryMessenger;

Map<String, Object?> _snapshot({required bool allowed, int revision = 1}) => {
      'version': 1,
      'delaySeconds': 60,
      'bootCount': 5,
      'deadlineElapsedMs': null,
      'state': allowed ? 'interactive' : 'locked',
      'elapsedRealtimeMs': 1000,
      'allowed': allowed,
      'revision': revision,
      'shieldGeneration': 1,
      'deviceInteractive': true,
    };

Future<void> _event(WidgetTester tester, Map<String, Object?> state) async {
  final reply = Completer<ByteData?>();
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      AndroidAppAccess.channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('accessStateChanged', state)),
      reply.complete);
  await reply.future;
}
