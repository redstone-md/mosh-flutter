import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/bind_interface_field.dart';
import 'package:mosh/src/features/vpn/vpn_consent_modal.dart';
import 'package:mosh/src/rust/api/vpn.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/rust/vpn_consent.dart';

import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

ScriptableBridge _bridge() => ScriptableBridge()
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
        isDefaultRoute: true)
  ])
  ..seedVpnDetection(const VpnDetection(
      vpnLikely: true,
      suspectInterfaces: ['Tunnel'],
      vpnOwnsDefaultRoute: true));

void main() {
  testWidgets('delayed consent prompt respects a choice saved in settings',
      (tester) async {
    final bridge = _bridge();
    final consent = Completer<VpnBypassConsent?>();
    bridge.respondNext(BridgeMethod.getVpnBypassConsent, consent.future);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await pumpScreen(
        tester,
        Scaffold(
            body: Stack(children: [
          VpnConsentModal(bridge: bridge, l: l, onAccept: () async {}),
          BindInterfaceField(bridge: bridge, l: l, onAccept: () async {}),
        ])));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    consent.complete(null);
    await tester.pumpAndSettle();
    expect(find.text(l.vpnConsentTitle), findsNothing);
    expect(bridge.countOf(BridgeMethod.setVpnBypassConsent), 1);
  });

  testWidgets(
      'consent restart failure offers restart retry without saving again',
      (tester) async {
    final bridge = _bridge();
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    var restarts = 0;
    await pumpScreen(
        tester,
        Scaffold(
            body: VpnConsentModal(
                bridge: bridge,
                l: l,
                onAccept: () async {
                  if (++restarts == 1) {
                    throw StateError('replacement unavailable');
                  }
                })));
    await tester.tap(find.text(l.vpnConsentAccept));
    await tester.pumpAndSettle();
    expect(find.text(l.bindAdapterRestartError), findsOneWidget);
    await tester.tap(find.text(l.vpnConsentAccept));
    await tester.pumpAndSettle();
    expect(restarts, 2);
    expect(bridge.countOf(BridgeMethod.setVpnBypassConsent), 1);
  });
}
