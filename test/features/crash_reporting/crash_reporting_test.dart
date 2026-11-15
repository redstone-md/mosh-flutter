// Opt-in crash reporting (ADR 0035): the SDK starts only with consent and a
// build DSN, and an opt-out stops it before forgetting the consent.
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/crash_reporting/crash_reporting.dart';
import 'package:mosh/src/features/crash_reporting/crash_reporting_toggle.dart';

import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

class _Sdk {
  final List<String> events = [];

  CrashReporting reporting(ScriptableBridge bridge, {String dsn = 'dsn'}) =>
      CrashReporting(
        bridge: bridge,
        dsn: dsn,
        start: (dsn, salt) async => events.add('start $salt'),
        stop: () async => events.add('stop'),
        capture: (event) =>
            events.add('capture ${event.exceptions!.single.type}'),
      );
}

void main() {
  test('launch starts the SDK only for an opted-in install', () async {
    final sdk = _Sdk();
    final optedOut = ScriptableBridge();
    await sdk.reporting(optedOut).resume();
    expect(sdk.events, isEmpty, reason: 'off by default');
    expect(optedOut.callsTo(BridgeMethod.stopEventCapture), isNotEmpty,
        reason: 'failures held until the consent was read are dropped');

    final optedIn = ScriptableBridge()..seedCrashReportingSalt('s1');
    await sdk.reporting(optedIn).resume();
    expect(sdk.events, ['start s1']);
  });

  test('a build without a DSN never starts, even with consent', () async {
    final sdk = _Sdk();
    final bridge = ScriptableBridge()..seedCrashReportingSalt('s1');
    final reporting = sdk.reporting(bridge, dsn: '');
    await reporting.resume();
    expect(reporting.available, isFalse);
    expect(sdk.events, isEmpty);
    expect(bridge.callsTo(BridgeMethod.stopEventCapture), isNotEmpty);
  });

  test('an unreadable consent still drops the failures Rust held', () async {
    final sdk = _Sdk();
    final bridge = ScriptableBridge()
      ..failNext(BridgeMethod.crashReportingSalt);
    await sdk.reporting(bridge).resume();
    expect(sdk.events, isEmpty);
    expect(bridge.callsTo(BridgeMethod.stopEventCapture), isNotEmpty);
  });

  test('a failed start leaves the install opted out', () async {
    final bridge = ScriptableBridge();
    final reporting = CrashReporting(
      bridge: bridge,
      dsn: 'dsn',
      start: (dsn, salt) async => throw StateError('sdk down'),
      stop: () async {},
    );
    await expectLater(reporting.setEnabled(true), throwsStateError);
    expect(await bridge.crashReportingSalt(), isNull,
        reason: 'a switch shown off must not report on the next launch');
  });

  test('opt-out stops the SDK and forgets the consent', () async {
    final sdk = _Sdk();
    final bridge = ScriptableBridge()..seedCrashReportingSalt('s1');
    await sdk.reporting(bridge).setEnabled(false);
    expect(sdk.events, ['stop']);
    expect(await bridge.crashReportingSalt(), isNull);
  });

  test('Rust panics are forwarded while on, and not after opt-out', () async {
    final sdk = _Sdk();
    final bridge = ScriptableBridge()..seedCrashReportingSalt('s1');
    final reporting = sdk.reporting(bridge);
    final panic =
        File('test/fixtures/rust_panic_event.json').readAsStringSync();

    await reporting.resume();
    bridge.rustEvents.add(panic);
    await pumpEventQueue();
    expect(sdk.events, ['start s1', 'capture panic']);

    await reporting.setEnabled(false);
    bridge.rustEvents.add(panic);
    await pumpEventQueue();
    expect(sdk.events, ['start s1', 'capture panic', 'stop']);
    expect(bridge.callsTo(BridgeMethod.stopEventCapture), isNotEmpty);
  });

  test('a Rust failure arrives as a message event', () {
    final event =
        rustEventFromJson('{"event_id":"0123456789abcdef0123456789abcdef",'
            '"timestamp":1700000000.5,"message":"startup: shared resources"}');
    expect(event.message?.formatted, 'startup: shared resources');
  });

  test('a malformed Rust event does not escape or stop later reports',
      () async {
    final sdk = _Sdk();
    final bridge = ScriptableBridge()..seedCrashReportingSalt('s1');
    final reporting = sdk.reporting(bridge);
    await reporting.resume();
    addTearDown(() => reporting.setEnabled(false));
    bridge.rustEvents.add('{invalid');
    bridge.rustEvents
        .add(File('test/fixtures/rust_panic_event.json').readAsStringSync());
    await pumpEventQueue();
    expect(sdk.events, ['start s1', 'capture panic']);
  });

  test('an asynchronous capture failure stays inside the reporter', () async {
    final bridge = ScriptableBridge()..seedCrashReportingSalt('s1');
    var attempts = 0;
    final reporting = CrashReporting(
      bridge: bridge,
      dsn: 'dsn',
      start: (_, __) async {},
      stop: () async {},
      capture: (_) async {
        if (++attempts == 1) throw StateError('capture unavailable');
      },
    );
    await reporting.resume();
    addTearDown(() => reporting.setEnabled(false));
    final panic =
        File('test/fixtures/rust_panic_event.json').readAsStringSync();
    bridge.rustEvents.add(panic);
    await pumpEventQueue();
    bridge.rustEvents.add(panic);
    await pumpEventQueue();
    expect(attempts, 2);
  });

  testWidgets('switching on records consent and starts reporting',
      (tester) async {
    final sdk = _Sdk();
    final bridge = ScriptableBridge();
    await pumpScreen(
      tester,
      const Scaffold(body: CrashReportingToggle()),
      overrides: [
        crashReportingProvider.overrideWithValue(sdk.reporting(bridge)),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(sdk.events, ['start scripted-salt']);
    expect(bridge.callsTo(BridgeMethod.enableCrashReporting), isNotEmpty);
  });
}
