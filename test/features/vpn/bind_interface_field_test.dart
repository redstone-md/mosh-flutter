// Tests for `BindInterfaceField` (lib/src/features/vpn/
// bind_interface_field.dart). Asserts the bound/unbound head copy, the
// no-NIC hint, the Bind/Release button label swap + onAccept, and the
// error branch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/bind_interface_field.dart';
import '../../support/scriptable_bridge.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import '../../support/pump.dart';

/// A gateway with [interfaces] as the machine's NICs and [bind] as the one
/// Mosh is bound to.
ScriptableBridge _bindGateway({
  required List<NetworkInterfaceInfo> interfaces,
  String? bind,
  bool failSetConsent = false,
}) {
  final gateway = ScriptableBridge()
    ..seedInterfaces(interfaces)
    ..seedBindInterface(bind);
  if (failSetConsent) {
    gateway.failAlways(BridgeMethod.setVpnBypassConsent,
        error: Exception('boom'));
  }
  return gateway;
}

NetworkInterfaceInfo _iface({
  required String name,
  String? ipv4,
}) =>
    NetworkInterfaceInfo(
      name: name,
      description: '',
      index: 0,
      ipv4: ipv4,
      isLoopback: false,
      isUp: true,
      isVirtual: false,
      isVpn: false,
      isDefaultRoute: false,
    );

Future<AppLocalizations> _l() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  required ScriptableBridge gateway,
  Future<void> Function()? onAccept,
}) async {
  onAccept ??= () async {};
  await pumpScreen(
      tester,
      Scaffold(
        body: BindInterfaceField(
          bridge: gateway,
          l: await _l(),
          onAccept: onAccept,
        ),
      ));
}

void main() {
  testWidgets(
    'unbound: shows the unbound body + Bind button',
    (tester) async {
      final gateway = _bindGateway(
        bind: null,
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      await _pump(tester, gateway: gateway);
      expect(find.text('Network adapter'), findsOneWidget);
      expect(
        find.text('Use a physical NIC when a VPN blocks peer discovery.'),
        findsOneWidget,
      );
      expect(find.text('Bind'), findsOneWidget);
      expect(find.text('Release'), findsNothing);
    },
  );

  testWidgets(
    'bound: shows the bound body + Release button + active line',
    (tester) async {
      final gateway = _bindGateway(
        bind: 'eth0',
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      await _pump(tester, gateway: gateway);
      expect(find.text('Mosh is bound to eth0.'), findsOneWidget);
      expect(find.text('Release'), findsOneWidget);
      expect(find.text('Bind'), findsNothing);
      expect(find.text('Every conversation uses eth0.'), findsOneWidget);
    },
  );

  testWidgets(
    'no physical NIC: shows the no-NIC hint + no Bind button',
    (tester) async {
      final gateway = _bindGateway(
        bind: null,
        interfaces: [_iface(name: 'tun0', ipv4: '10.8.0.1')],
      );
      // tun0 isVirtual=true is filtered out by bypassCandidates; force it.
      // (Re-test with a virtual iface so no candidate survives.)
      gateway.seedInterfaces([
        NetworkInterfaceInfo(
          name: 'tun0',
          description: '',
          index: 0,
          ipv4: '10.8.0.1',
          isLoopback: false,
          isUp: true,
          isVirtual: true,
          isVpn: false,
          isDefaultRoute: false,
        ),
      ]);
      await _pump(tester, gateway: gateway);
      expect(find.text('No connected physical NIC detected.'), findsOneWidget);
      expect(find.text('Bind'), findsNothing);
    },
  );

  testWidgets(
    'Bind records the picked adapter + fires onAccept',
    (tester) async {
      final gateway = _bindGateway(
        bind: null,
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      var acceptCount = 0;
      await _pump(
        tester,
        gateway: gateway,
        onAccept: () async {
          acceptCount++;
        },
      );
      await tester.tap(find.text('Bind'));
      await tester.pumpAndSettle();
      expect(gateway.countOf(BridgeMethod.setVpnBypassConsent), 1);
      expect(
          gateway
              .lastCall(BridgeMethod.setVpnBypassConsent)
              ?.arg<String?>('interfaceName'),
          'eth0');
      expect(acceptCount, 1);
    },
  );

  testWidgets(
    'Release clears the override + fires onAccept',
    (tester) async {
      final gateway = _bindGateway(
        bind: 'eth0',
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      var acceptCount = 0;
      await _pump(
        tester,
        gateway: gateway,
        onAccept: () async {
          acceptCount++;
        },
      );
      await tester.tap(find.text('Release'));
      await tester.pumpAndSettle();
      expect(gateway.countOf(BridgeMethod.setVpnBypassConsent), 1);
      expect(
          gateway
              .lastCall(BridgeMethod.setVpnBypassConsent)
              ?.arg<String?>('interfaceName'),
          isNull);
      expect(acceptCount, 1);
    },
  );

  testWidgets(
    'apply failure surfaces the error',
    (tester) async {
      final gateway = _bindGateway(
        bind: null,
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
        failSetConsent: true,
      );
      await _pump(tester, gateway: gateway);
      await tester.tap(find.text('Bind'));
      await tester.pumpAndSettle();
      // The error text surfaces (Exception.toString form).
      expect(find.textContaining('Exception'), findsOneWidget);
    },
  );
}
