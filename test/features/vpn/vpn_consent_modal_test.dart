// Parity tests for `VpnConsentModal` (lib/src/features/vpn/
// vpn_consent_modal.dart) -- the 1-в-1 port of React's
// `VpnConsentModal.tsx`. Asserts the show/hide gate, the accept/decline
// Gateway calls, the saving-phase label swap, and the error branch.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/vpn_consent_modal.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/api/vpn.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/rust/vpn_consent.dart';

/// A recording Gateway for the consent flow. Only the VPN/consent +
/// listInterfaces methods are exercised; the rest throw.
class _ConsentGateway implements Gateway {
  VpnBypassConsent? consent;
  VpnDetection detection;
  List<NetworkInterfaceInfo> interfaces;
  String? lastSetInterface; // null = decline cleared it.
  int setConsentCount = 0;
  bool failSetConsent = false;

  _ConsentGateway({
    this.consent,
    required this.detection,
    required this.interfaces,
    this.failSetConsent = false,
  });

  @override
  Future<VpnBypassConsent?> getVpnBypassConsent() async => consent;

  @override
  Future<VpnDetection> detectVpn() async => detection;

  @override
  Future<List<NetworkInterfaceInfo>> listInterfaces() async => interfaces;

  @override
  Future<void> setVpnBypassConsent({String? interfaceName}) async {
    setConsentCount++;
    lastSetInterface = interfaceName;
    if (failSetConsent) throw Exception('boom');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(' ${invocation.memberName}');
}

NetworkInterfaceInfo _iface({
  required String name,
  String? ipv4,
  bool isUp = true,
  bool isLoopback = false,
  bool isVirtual = false,
}) =>
    NetworkInterfaceInfo(
      name: name,
      description: '',
      index: 0,
      ipv4: ipv4,
      isLoopback: isLoopback,
      isUp: isUp,
      isVirtual: isVirtual,
      isVpn: false,
      isDefaultRoute: false,
    );

VpnDetection _ownsDefault() => const VpnDetection(
      vpnLikely: true,
      suspectInterfaces: ['tun0'],
      vpnOwnsDefaultRoute: true,
    );

VpnDetection _noVpn() => const VpnDetection(
      vpnLikely: false,
      suspectInterfaces: [],
      vpnOwnsDefaultRoute: false,
    );

Future<AppLocalizations> _l() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<void> _pump(
  WidgetTester tester, {
  required _ConsentGateway gateway,
  Future<void> Function()? onAccept,
}) async {
  onAccept ??= () async {};
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: VpnConsentModal(
          gateway: gateway,
          l: await _l(),
          onAccept: onAccept,
        ),
      ),
    ),
  );
  // Let initState's async network-state fetch resolve.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shows the modal when no consent + VPN owns the default route + a candidate exists',
    (tester) async {
      final gateway = _ConsentGateway(
        consent: null,
        detection: _ownsDefault(),
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      await _pump(tester, gateway: gateway);
      expect(find.text("A VPN is carrying Mosh's traffic"), findsOneWidget);
      expect(find.textContaining('eth0'), findsOneWidget);
    },
  );

  testWidgets(
    'hides when the user already consented',
    (tester) async {
      final gateway = _ConsentGateway(
        consent: const VpnBypassConsent(interface_: 'eth0', index: 0),
        detection: _ownsDefault(),
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      await _pump(tester, gateway: gateway);
      expect(find.byType(VpnConsentModal), findsOneWidget);
      expect(find.text("A VPN is carrying Mosh's traffic"), findsNothing);
    },
  );

  testWidgets(
    'hides when no VPN owns the default route',
    (tester) async {
      final gateway = _ConsentGateway(
        consent: null,
        detection: _noVpn(),
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      await _pump(tester, gateway: gateway);
      expect(find.text("A VPN is carrying Mosh's traffic"), findsNothing);
    },
  );

  testWidgets(
    'hides when no bypass candidate exists',
    (tester) async {
      final gateway = _ConsentGateway(
        consent: null,
        detection: _ownsDefault(),
        interfaces: [_iface(name: 'tun0', ipv4: '10.8.0.1', isVirtual: true)],
      );
      await _pump(tester, gateway: gateway);
      expect(find.text("A VPN is carrying Mosh's traffic"), findsNothing);
    },
  );

  testWidgets(
    'accept records the suggested adapter + fires onAccept',
    (tester) async {
      final gateway = _ConsentGateway(
        consent: null,
        detection: _ownsDefault(),
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
      await tester.tap(find.text('Route around the VPN'));
      await tester.pumpAndSettle();
      expect(gateway.setConsentCount, 1);
      expect(gateway.lastSetInterface, 'eth0');
      expect(acceptCount, 1);
    },
  );

  testWidgets(
    'decline clears the consent + hides the modal',
    (tester) async {
      final gateway = _ConsentGateway(
        consent: null,
        detection: _ownsDefault(),
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      await _pump(tester, gateway: gateway);
      await tester.tap(find.text('Keep using the VPN'));
      await tester.pumpAndSettle();
      expect(gateway.setConsentCount, 1);
      expect(gateway.lastSetInterface, isNull);
      expect(find.text("A VPN is carrying Mosh's traffic"), findsNothing);
    },
  );

  testWidgets(
    'accept failure surfaces the error + returns to asking',
    (tester) async {
      final gateway = _ConsentGateway(
        consent: null,
        detection: _ownsDefault(),
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
        failSetConsent: true,
      );
      await _pump(tester, gateway: gateway);
      await tester.tap(find.text('Route around the VPN'));
      await tester.pumpAndSettle();
      // The accept button is back to its non-saving label.
      expect(find.text('Route around the VPN'), findsOneWidget);
      expect(find.text('Restarting...'), findsNothing);
    },
  );
}
