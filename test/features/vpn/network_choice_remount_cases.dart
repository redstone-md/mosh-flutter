import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/bind_interface_field.dart';
import 'package:mosh/src/rust/network_inventory.dart';

import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

void main() {
  testWidgets('saved restart knowledge survives closing connection settings',
      (tester) async {
    final bridge = ScriptableBridge()
      ..seedInterfaces(const [
        NetworkInterfaceInfo(
            name: 'Ethernet',
            description: '',
            index: 1,
            ipv4: '192.168.1.5',
            isUp: true,
            isLoopback: false,
            isVirtual: false,
            isVpn: false,
            isDefaultRoute: true),
      ]);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    Widget field() => Scaffold(
        body: BindInterfaceField(
            bridge: bridge,
            l: l,
            onAccept: () async {
              throw StateError('replacement unavailable');
            }));
    await pumpScreen(tester, field(), container: container);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await pumpScreen(tester, const Scaffold(), container: container);
    await pumpScreen(tester, field(), container: container);
    expect(find.text(l.bindAdapterRestartNeeded), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    expect(bridge.countOf(BridgeMethod.getBindInterface), 0);
  });
}
