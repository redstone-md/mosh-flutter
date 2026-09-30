// Opt-in crash reporting (ADR 0035): the SDK starts only with consent and a
// build DSN, and an opt-out stops it before forgetting the consent.
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
      );
}

void main() {
  test('launch starts the SDK only for an opted-in install', () async {
    final sdk = _Sdk();
    await sdk.reporting(ScriptableBridge()).resume();
    expect(sdk.events, isEmpty, reason: 'off by default');

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
  });

  test('opt-out stops the SDK and forgets the consent', () async {
    final sdk = _Sdk();
    final bridge = ScriptableBridge()..seedCrashReportingSalt('s1');
    await sdk.reporting(bridge).setEnabled(false);
    expect(sdk.events, ['stop']);
    expect(await bridge.crashReportingSalt(), isNull);
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
