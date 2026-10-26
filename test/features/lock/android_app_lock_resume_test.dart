import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';
import 'package:mosh/src/features/lock/android_app_lock_gate.dart';
import '../../support/pump.dart';

void main() {
  testWidgets(
      'returning from call-only UI validates expiry before painting chats',
      (tester) async {
    var reads = 0;
    final resumed = Completer<Object?>();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel, (call) async {
      if (call.method == 'readAccessState' && ++reads > 1) {
        return resumed.future;
      }
      return _state('grace', 1);
    });
    final access = AndroidAppAccess();
    await access.initialize();
    final visible = ValueNotifier(false);
    await pumpScreen(
        tester,
        ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, interactive, __) => Stack(children: [
                  AndroidAppLockGate(
                      interactive: interactive,
                      child: const Scaffold(body: Text('protected chat'))),
                  const Align(
                      alignment: Alignment.topCenter,
                      child: Text('call controls')),
                ])),
        overrides: [androidAppAccessProvider.overrideWithValue(access)]);
    expect(find.text('protected chat'), findsNothing);
    expect(find.text('call controls'), findsOneWidget);
    visible.value = true;
    await tester.pump();
    expect(find.text('protected chat'), findsNothing,
        reason:
            'an old grace snapshot is insufficient for the returning frame');
    resumed.complete(_state('locked', 2));
    await tester.pumpAndSettle();
    expect(find.text('protected chat'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('call controls'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    access.dispose();
    visible.dispose();
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel, null);
  });
}

Map<String, Object?> _state(String phase, int revision) => {
      'version': 1,
      'delaySeconds': 60,
      'bootCount': 5,
      'deadlineElapsedMs': phase == 'grace' ? 61000 : null,
      'state': phase,
      'elapsedRealtimeMs': 1000,
      'allowed': phase != 'locked',
      'revision': revision,
      'shieldGeneration': 1,
      'deviceInteractive': true,
    };
