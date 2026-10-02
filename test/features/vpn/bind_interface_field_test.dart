// Tests for `BindInterfaceField` (lib/src/features/vpn/
// bind_interface_field.dart). Asserts the bound/unbound head copy, the
// no-NIC hint, the Apply/Reset button label swap + onAccept, and the
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
  bool settle = true,
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
      ),
      settle: settle);
}

void main() {
  testWidgets('pending reads offer no actionable adapter until they complete',
      (tester) async {
    final gateway = _bindGateway(
      interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
    )..hold(BridgeMethod.listInterfaces);
    await _pump(tester, gateway: gateway, settle: false);
    expect(find.text('Apply'), findsNothing);
    expect(gateway.countOf(BridgeMethod.setVpnBypassConsent), 0);
    gateway.release(BridgeMethod.listInterfaces);
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('read failure offers refresh and recovers without writing',
      (tester) async {
    final gateway = _bindGateway(
      interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
    )..failNext(BridgeMethod.getBindInterface);
    await _pump(tester, gateway: gateway);
    expect(find.text('Could not read network state'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh devices'));
    await tester.pumpAndSettle();
    expect(find.text('Could not read network state'), findsNothing);
    expect(find.text('Apply'), findsOneWidget);
    expect(gateway.countOf(BridgeMethod.setVpnBypassConsent), 0);
  });

  testWidgets(
      'failed relaunch retains the saved choice and restart instructions',
      (tester) async {
    final gateway = _bindGateway(
      interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
    );
    await _pump(tester, gateway: gateway, onAccept: () async {
      throw StateError('replacement could not start');
    });
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Saved adapter: eth0.'), findsOneWidget);
    expect(find.textContaining('Saved, but Mosh could not restart'),
        findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Reset'))
            .onPressed,
        isNotNull);
  });

  testWidgets('pending write blocks duplicates and relaunches after disposal',
      (tester) async {
    final gateway = _bindGateway(
      interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
    )..hold(BridgeMethod.setVpnBypassConsent);
    var restarts = 0;
    await _pump(tester, gateway: gateway, onAccept: () async => restarts++);
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Saving…'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    gateway.release(BridgeMethod.setVpnBypassConsent);
    await tester.pumpAndSettle();
    expect(restarts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful apply releases the controls when relaunch returns',
      (tester) async {
    final gateway = _bindGateway(
      interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
    );
    await _pump(tester, gateway: gateway);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final reset = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Reset'));
    expect(reset.onPressed, isNotNull);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(gateway.countOf(BridgeMethod.setVpnBypassConsent), 2);
    expect(
        gateway
            .lastCall(BridgeMethod.setVpnBypassConsent)
            ?.arg<String?>('interfaceName'),
        isNull);
  });

  testWidgets('a disconnected saved adapter can still be reset',
      (tester) async {
    final gateway = _bindGateway(interfaces: [], bind: 'eth0');
    await _pump(tester, gateway: gateway);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(
        gateway
            .lastCall(BridgeMethod.setVpnBypassConsent)
            ?.arg<String?>('interfaceName'),
        isNull);
    expect(gateway.countOf(BridgeMethod.setVpnBypassConsent), 1);
  });

  testWidgets('releasing a missing adapter offers a connected replacement',
      (tester) async {
    final gateway = _bindGateway(
        bind: 'old-ethernet',
        interfaces: [_iface(name: 'wifi', ipv4: '192.168.1.8')]);
    await _pump(tester, gateway: gateway);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('wifi - 192.168.1.8'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
        gateway
            .lastCall(BridgeMethod.setVpnBypassConsent)
            ?.arg<String?>('interfaceName'),
        'wifi');
  });

  testWidgets('adapter choice stays local until Apply saves the selected NIC',
      (tester) async {
    final gateway = _bindGateway(interfaces: [
      _iface(name: 'eth0', ipv4: '192.168.1.5'),
      _iface(name: 'eth1', ipv4: '192.168.1.6'),
    ]);
    await _pump(tester, gateway: gateway);
    await tester.tap(find.text('eth0 - 192.168.1.5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('eth1 - 192.168.1.6'));
    await tester.pumpAndSettle();
    expect(gateway.countOf(BridgeMethod.setVpnBypassConsent), 0);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
        gateway
            .lastCall(BridgeMethod.setVpnBypassConsent)
            ?.arg<String?>('interfaceName'),
        'eth1');
  });

  testWidgets(
    'unbound: shows the unbound body + Apply button',
    (tester) async {
      final gateway = _bindGateway(
        bind: null,
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      await _pump(tester, gateway: gateway);
      expect(
        find.text('Choose your network adapter, such as Ethernet or Wi-Fi.'),
        findsOneWidget,
      );
      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('Reset'), findsNothing);
    },
  );

  testWidgets(
    'bound: shows the bound body + Reset button + restart notice',
    (tester) async {
      final gateway = _bindGateway(
        bind: 'eth0',
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      await _pump(tester, gateway: gateway);
      expect(find.text('Saved adapter: eth0.'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
      expect(find.textContaining('restarts after applying'), findsOneWidget);
    },
  );

  testWidgets(
    'no physical NIC: shows the no-NIC hint + no Apply button',
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
      expect(find.text('No connected physical adapter found.'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
    },
  );

  testWidgets(
    'Apply records the picked adapter + fires onAccept',
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
      await tester.tap(find.text('Apply'));
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
    'Reset clears the override + fires onAccept',
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
      await tester.tap(find.text('Reset'));
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
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Could not apply override'), findsOneWidget);
    },
  );
}
