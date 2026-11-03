import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/bind_interface_field.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/rust/vpn_consent.dart';

import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

const _adapter = NetworkInterfaceInfo(
    name: 'Ethernet',
    description: '',
    index: 1,
    ipv4: '192.168.1.5',
    isUp: true,
    isLoopback: false,
    isVirtual: false,
    isVpn: false,
    isDefaultRoute: true);
const _consent = VpnBypassConsent(interface_: 'Ethernet', index: 1);

Future<void> _pump(WidgetTester tester, ScriptableBridge bridge) async {
  final l = await AppLocalizations.delegate.load(const Locale('en'));
  await pumpScreen(
      tester,
      Scaffold(
          body:
              BindInterfaceField(bridge: bridge, l: l, onAccept: () async {})));
}

void main() {
  for (final saved in [true, false]) {
    testWidgets('saved bypass $saved wins over the opposite runtime binding',
        (tester) async {
      final bridge = ScriptableBridge()
        ..seedInterfaces([_adapter])
        ..seedVpnConsent(saved ? _consent : null)
        ..seedBindInterface(saved ? null : 'Ethernet');
      await _pump(tester, bridge);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          saved);
      expect(find.text(saved ? 'On' : 'Off'), findsOneWidget);
      expect(bridge.countOf(BridgeMethod.getBindInterface), 0);
      expect(bridge.countOf(BridgeMethod.getVpnBypassConsent), 1);
    });

    testWidgets('changed bypass survives a fresh settings widget: $saved',
        (tester) async {
      final bridge = ScriptableBridge()
        ..seedInterfaces([_adapter])
        ..seedVpnConsent(saved ? _consent : null);
      await _pump(tester, bridge);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(bridge.countOf(BridgeMethod.setVpnBypassConsent), 1);
      expect((await bridge.getVpnBypassConsent()) != null, !saved);
      // Disposing the entire field discards its optimistic/local state.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, bridge);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          !saved);
      expect(find.text(saved ? 'Off' : 'On'), findsOneWidget);
      expect(bridge.countOf(BridgeMethod.getBindInterface), 0);
    });
  }
}
