import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/connection_settings_section.dart';
import 'package:mosh/src/features/settings/settings_content.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

Future<void> _pump(WidgetTester tester, ScriptableBridge bridge,
    {Widget? section, double textScale = 1, bool settle = true}) async {
  final container = ProviderContainer(
    overrides: [bridgeFacadeProvider.overrideWithValue(bridge)],
    retry: (_, __) => null,
  );
  addTearDown(container.dispose);
  await pumpScreen(
      tester,
      Theme(
        data: buildMoshTheme(),
        child: Builder(
            builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: Scaffold(
                      body: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: section ?? const ConnectionSettingsSection())),
                )),
      ),
      container: container,
      settle: settle);
}

Future<void> _open(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

ScriptableBridge _bridge() => ScriptableBridge()
  ..seedInterfaces([
    const NetworkInterfaceInfo(
        name: 'Ethernet',
        description: '',
        index: 1,
        ipv4: '192.168.1.5',
        isUp: true,
        isLoopback: false,
        isVirtual: false,
        isVpn: false,
        isDefaultRoute: true)
  ]);

void main() {
  testWidgets('VPN interfaces load only when their controls are opened',
      (tester) async {
    final bridge = _bridge();
    await _pump(tester, bridge);
    expect(bridge.countOf(BridgeMethod.listInterfaces), 0);
    expect(bridge.countOf(BridgeMethod.nativeRuntimeStatus), 0);
    expect(bridge.countOf(BridgeMethod.mossLibraryInfo), 0);
    await _open(tester, 'If a VPN gets in the way');
    expect(bridge.countOf(BridgeMethod.listInterfaces), 1);
    expect(find.text('Apply'), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.nativeRuntimeStatus), 0);
  });

  testWidgets(
      'unsupported relaunch saves and shows manual restart after collapse',
      (tester) async {
    final bridge = _bridge();
    await _pump(tester, bridge);
    await _open(tester, 'If a VPN gets in the way');
    expect(find.textContaining('After saving, close Mosh completely'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
        bridge
            .lastCall(BridgeMethod.setVpnBypassConsent)
            ?.arg<String?>('interfaceName'),
        'Ethernet');
    expect(find.textContaining('Saved. Close Mosh completely'), findsOneWidget);
    await _open(tester, 'If a VPN gets in the way');
    await _open(tester, 'If a VPN gets in the way');
    expect(find.textContaining('Saved. Close Mosh completely'), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.listInterfaces), 1);
  });

  testWidgets('read receipts live in Privacy and retain the real write seam',
      (tester) async {
    final bridge = _bridge();
    await _pump(tester, bridge,
        section: const SettingsContent(
            section: SettingsSection.privacy, wide: false));
    expect(find.text('Read receipts'), findsOneWidget);
    final toggle = find.byType(SwitchListTile).last;
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
        bridge
            .lastCall(BridgeMethod.setReadReceiptsEnabled)
            ?.arg<bool>('enabled'),
        isTrue);
  });

  testWidgets('320px with enlarged text keeps the expanded VPN controls usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bridge = _bridge();
    await _pump(tester, bridge, textScale: 2);
    await _open(tester, 'If a VPN gets in the way');
    await tester.ensureVisible(find.byTooltip('Refresh devices'));
    expect(find.text('Apply'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
