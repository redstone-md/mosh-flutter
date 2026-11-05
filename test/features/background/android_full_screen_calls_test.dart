import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/background/android_waiting_owner.dart';
import 'package:mosh/src/features/background/android_waiting_settings.dart';
import 'package:mosh/src/features/background/background_commands.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';

import '../../support/pump.dart';

Map<String, Object?> state({required bool fullScreen}) => {
      'revision': fullScreen ? 2 : 1,
      'intentRevision': 1,
      'interactive': true,
      'waitingEnabled': true,
      'serviceRunning': true,
      'setupComplete': true,
      'notificationsAllowed': true,
      'batteryExempt': true,
      'fullScreenCallsAllowed': fullScreen,
    };

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> requests;
  late bool granted;

  setUp(() {
    requests = [];
    granted = false;
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidWaitingPlatform.channel, (call) async {
      if (call.method == 'requestFullScreenCalls') {
        requests.add(call.method);
        granted = true;
      }
      return state(fullScreen: granted);
    });
  });
  tearDown(() => binding.defaultBinaryMessenger
      .setMockMethodCallHandler(AndroidWaitingPlatform.channel, null));

  Future<void> pumpSettings(WidgetTester tester) async {
    final platform = AndroidWaitingPlatform();
    addTearDown(platform.dispose);
    await platform.refresh();
    final owner = AndroidWaitingOwner(platform, BackgroundCommands());
    addTearDown(owner.dispose);
    await pumpScreen(
      tester,
      const Scaffold(
          body: SingleChildScrollView(child: AndroidWaitingSettings())),
      overrides: [androidWaitingOwnerProvider.overrideWithValue(owner)],
    );
  }

  testWidgets('calls on the lock screen open Android settings only once agreed',
      (tester) async {
    await pumpSettings(tester);
    final action =
        find.widgetWithText(TextButton, 'Show calls on the lock screen');

    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);

    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find
        .descendant(
            of: find.byType(Dialog),
            matching: find.text('Show calls on the lock screen'))
        .last);
    await tester.pumpAndSettle();
    expect(requests, ['requestFullScreenCalls']);
    expect(action, findsNothing, reason: 'granted, so nothing to ask');
  });
}
