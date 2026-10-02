import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/settings_screen.dart';
import 'package:mosh/src/features/settings/settings_content.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/rust/network_inventory.dart';

import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/settings.dart';

Future<void> _pump(WidgetTester tester,
    {double width = 1200,
    double height = 900,
    ScriptableBridge? bridge}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpScreen(
      tester,
      Theme(
          data: buildMoshTheme().copyWith(platform: TargetPlatform.windows),
          child: const SettingsScreen()),
      overrides: [
        ...settingsAudioOverrides(),
        bridgeFacadeProvider.overrideWithValue(bridge ?? ScriptableBridge()),
      ]);
  await _tap(tester, 'Connection');
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adapter menu opens inside the expanded Connection section',
      (tester) async {
    final bridge = ScriptableBridge()
      ..seedInterfaces(
          [_iface('Ethernet', '192.168.1.5'), _iface('Wi-Fi', '192.168.1.6')]);
    await _pump(tester, bridge: bridge);
    await _tap(tester, 'If a VPN gets in the way');
    await _tap(tester, 'Ethernet - 192.168.1.5');
    expect(tester.takeException(), isNull);
    await _tap(tester, 'Wi-Fi - 192.168.1.6');
    expect(bridge.countOf(BridgeMethod.setVpnBypassConsent), 0);
    expect(find.text('Wi-Fi - 192.168.1.6'), findsOneWidget);
  });

  testWidgets('scrolling an adapter menu leaves VPN state usable after return',
      (tester) async {
    final bridge = ScriptableBridge()
      ..seedInterfaces(
          [for (var i = 0; i < 20; i++) _iface('Adapter $i', '192.168.1.$i')]);
    await _pump(tester, bridge: bridge);
    await _tap(tester, 'If a VPN gets in the way');
    await _tap(tester, 'Adapter 0 - 192.168.1.0');
    final menuScroll = find.descendant(
        of: find.byType(MenuAnchor), matching: find.byType(Scrollable));
    tester.state<ScrollableState>(menuScroll).position.jumpTo(200);
    await tester.pumpAndSettle();
    // Material consumes the first outside tap to dismiss the menu.
    await _tap(tester, 'About');
    await _tap(tester, 'About');
    await _tap(tester, 'Connection');
    expect(tester.takeException(), isNull);
    expect(find.text('Adapter 0 - 192.168.1.0'), findsOneWidget);
    await _tap(tester, 'Adapter 0 - 192.168.1.0');
    await _tap(tester, 'Adapter 1 - 192.168.1.1');
    expect(tester.takeException(), isNull);
    expect(bridge.countOf(BridgeMethod.setVpnBypassConsent), 0);
  });

  testWidgets('restored VPN disclosure can be collapsed and reopened',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'If a VPN gets in the way');
    await _tap(tester, 'About');
    await _tap(tester, 'Connection');
    expect(tester.takeException(), isNull);
    expect(find.text('No connected physical adapter found.'), findsOneWidget);
    await _tap(tester, 'If a VPN gets in the way');
    expect(find.text('No connected physical adapter found.'), findsNothing);
    await _tap(tester, 'If a VPN gets in the way');
    expect(find.text('No connected physical adapter found.'), findsOneWidget);
  });

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

  testWidgets('returning to Connection shows the saved bypass switch on',
      (tester) async {
    final bridge = ScriptableBridge()
      ..seedBindInterface('Ethernet')
      ..seedInterfaces([_iface('Ethernet', '192.168.1.5')]);
    await _pump(tester, bridge: bridge);
    await _tap(tester, 'If a VPN gets in the way');
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    await _tap(tester, 'About');
    await _tap(tester, 'Connection');
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    expect(find.text('On'), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.setVpnBypassConsent), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connection restores scroll offset alongside open disclosures',
      (tester) async {
    await _pump(tester, height: 400);
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
    await _tap(tester, 'If a VPN gets in the way');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await _tap(tester, 'Connection');
    expect(tester.takeException(), isNull);
    expect(find.text('No connected physical adapter found.'), findsOneWidget);
  });
}

NetworkInterfaceInfo _iface(String name, String ipv4) => NetworkInterfaceInfo(
    name: name,
    ipv4: ipv4,
    description: '',
    index: 1,
    isUp: true,
    isLoopback: false,
    isVirtual: false,
    isVpn: false,
    isDefaultRoute: true);
