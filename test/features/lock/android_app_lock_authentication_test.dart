import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/lock/android_app_access.dart';
import 'package:mosh/src/features/lock/android_app_lock_gate.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('opening locked chats prompts once without tapping Retry',
      (tester) async {
    final authentication = Completer<String>();
    var allowed = false;
    var requests = 0;
    var revision = 0;
    await _mount(tester, (call) async {
      if (call.method == 'authenticateChats') {
        requests++;
        final outcome = await authentication.future;
        allowed = outcome == 'authenticated';
        return outcome;
      }
      return _state(allowed: allowed, revision: ++revision);
    }, settle: false);
    await tester.pump();
    expect(requests, 1);
    expect(find.text('protected chat'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(requests, 1,
        reason: 'a system dialog must not duplicate the prompt');
    authentication.complete('authenticated');
    await tester.pumpAndSettle();
    expect(find.text('protected chat'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('returning after a canceled unlock offers a fresh prompt',
      (tester) async {
    var requests = 0;
    var revision = 0;
    await _mount(tester, (call) async {
      if (call.method == 'authenticateChats') {
        requests++;
        return 'canceled';
      }
      return _state(allowed: false, revision: ++revision);
    });
    expect(requests, 1);
    expect(find.text('Retry'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(requests, 1,
        reason: 'cancel must not immediately reopen the prompt');
    _pause(tester);
    _resume(tester);
    await tester.pumpAndSettle();
    expect(requests, 2,
        reason: 'a later app entry must not require Retry first');
    expect(find.text('protected chat'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expired background grace prompts before restoring the draft',
      (tester) async {
    final authentication = Completer<String>();
    var allowed = true;
    var interactive = true;
    var requests = 0;
    var revision = 0;
    await _mount(tester, (call) async {
      if (call.method == 'authenticateChats') {
        requests++;
        allowed = await authentication.future == 'authenticated';
        return 'authenticated';
      }
      return _state(
          allowed: allowed, interactive: interactive, revision: ++revision);
    }, child: const TextField());
    await tester.enterText(find.byType(TextField), 'unsent draft');
    _pause(tester);
    interactive = false;
    allowed = false;
    await _event(tester,
        _state(allowed: false, interactive: false, revision: ++revision));
    await tester.pump();
    expect(find.text('unsent draft'), findsNothing);
    expect(requests, 0);
    interactive = true;
    await _event(tester, _state(allowed: false, revision: ++revision));
    _resume(tester);
    await tester.pump();
    await tester.pump();
    expect(requests, 1);
    expect(find.text('unsent draft'), findsNothing);
    authentication.complete('authenticated');
    await tester.pumpAndSettle();
    expect(find.text('unsent draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('device credential pause cannot restart a canceled prompt',
      (tester) async {
    final authentication = Completer<String>();
    var requests = 0;
    var revision = 0;
    await _mount(tester, (call) async {
      if (call.method == 'authenticateChats') {
        requests++;
        return authentication.future;
      }
      return _state(allowed: false, revision: ++revision);
    }, settle: false);
    await tester.pump();
    _pause(tester);
    authentication.complete('canceled');
    _resume(tester);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('protected chat'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('permission dialog preserves an existing chat grant',
      (tester) async {
    var requests = 0;
    var revision = 0;
    await _mount(tester, (call) async {
      if (call.method == 'authenticateChats') {
        requests++;
        return 'canceled';
      }
      return _state(allowed: true, revision: ++revision);
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _event(tester,
        _state(allowed: true, interactive: false, revision: ++revision));
    await tester.pump();
    expect(find.text('protected chat'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    await _event(tester, _state(allowed: true, revision: ++revision));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('protected chat'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _mount(
    WidgetTester tester, Future<Object?> Function(MethodCall) platform,
    {Widget child = const Text('protected chat'), bool settle = true}) async {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(AndroidAppAccess.channel, platform);
  final access = AndroidAppAccess();
  addTearDown(() {
    access.dispose();
    messenger.setMockMethodCallHandler(AndroidAppAccess.channel, null);
  });
  await access.initialize();
  await pumpScreen(tester, AndroidAppLockGate(child: Scaffold(body: child)),
      settle: settle,
      overrides: [androidAppAccessProvider.overrideWithValue(access)]);
}

Map<String, Object?> _state(
        {required bool allowed,
        required int revision,
        bool interactive = true}) =>
    {
      'version': 1,
      'delaySeconds': 60,
      'bootCount': 5,
      'deadlineElapsedMs': null,
      'state': allowed ? 'interactive' : 'locked',
      'elapsedRealtimeMs': 1000,
      'allowed': allowed,
      'revision': revision,
      'shieldGeneration': 1,
      'deviceInteractive': interactive,
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

void _pause(WidgetTester tester) {
  for (final phase in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused
  ]) {
    tester.binding.handleAppLifecycleStateChanged(phase);
  }
}

void _resume(WidgetTester tester) {
  for (final phase in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed
  ]) {
    tester.binding.handleAppLifecycleStateChanged(phase);
  }
}
