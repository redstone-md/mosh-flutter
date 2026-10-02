import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/settings_screen.dart';
import 'package:mosh/src/features/settings/settings_content.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/settings.dart';

Future<void> _pump(WidgetTester tester,
    {double width = 1200, double height = 900}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpScreen(
      tester, Theme(data: buildMoshTheme(), child: const SettingsScreen()),
      overrides: [
        ...settingsAudioOverrides(),
        bridgeFacadeProvider.overrideWithValue(ScriptableBridge()),
      ]);
  await _tap(tester, 'Connection');
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  for (final label in ['How it works', 'If a VPN gets in the way']) {
    testWidgets('Connection reopens after expanding $label', (tester) async {
      await _pump(tester);
      await _tap(tester, label);
      await _tap(tester, 'About');
      await _tap(tester, 'Connection');
      expect(tester.takeException(), isNull);
      expect(find.text('Automatic discovery'), findsOneWidget);
    });
  }

  testWidgets('restored VPN expansion contains its actual controls',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'If a VPN gets in the way');
    expect(find.text('No connected physical adapter found.'), findsOneWidget);
    await _tap(tester, 'About');
    await _tap(tester, 'Connection');
    expect(tester.takeException(), isNull);
    expect(find.text('No connected physical adapter found.'), findsOneWidget);
  });

  testWidgets('discovery and VPN disclosures restore independently',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'If a VPN gets in the way');
    await _tap(tester, 'About');
    await _tap(tester, 'Connection');
    expect(
        find.textContaining('establishes a route automatically'), findsNothing);
    expect(find.text('No connected physical adapter found.'), findsOneWidget);
    await _tap(tester, 'If a VPN gets in the way');
    await _tap(tester, 'How it works');
    await _tap(tester, 'About');
    await _tap(tester, 'Connection');
    expect(find.textContaining('establishes a route automatically'),
        findsOneWidget);
    expect(find.text('No connected physical adapter found.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connection restores scroll offset alongside open disclosures',
      (tester) async {
    await _pump(tester, height: 500);
    await _tap(tester, 'How it works');
    await _tap(tester, 'If a VPN gets in the way');
    final scroller = find.descendant(
        of: find.byType(SettingsContent), matching: find.byType(Scrollable));
    tester.state<ScrollableState>(scroller).position.jumpTo(50);
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(scroller).position.pixels;
    expect(offset, greaterThan(0));
    await _tap(tester, 'About');
    await _tap(tester, 'Connection');
    expect(tester.takeException(), isNull);
    expect(tester.state<ScrollableState>(scroller).position.pixels,
        closeTo(offset, 0.1));
    expect(find.text('No connected physical adapter found.'), findsOneWidget);
  });

  testWidgets('narrow Back and reopening preserve the usable Connection view',
      (tester) async {
    await _pump(tester, width: 390);
    await _tap(tester, 'How it works');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await _tap(tester, 'Connection');
    expect(tester.takeException(), isNull);
    expect(find.text('Automatic discovery'), findsOneWidget);
  });
}
