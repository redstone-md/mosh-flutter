// VPN bypass consent: the launch modal over the chat shell.
//
// MoshApp places VpnConsentOverlay in MaterialApp.builder, above the
// Navigator, where the dialog's close-button tooltip finds no Overlay and
// throws. The scenes keep the app's own overlay off and insert the same
// modal into the root navigator's overlay instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/features/vpn/vpn_consent_modal.dart';
import 'package:mosh/src/rust/api/vpn.dart';
import 'package:mosh/src/rust/network_inventory.dart';

import '../../../test/support/scriptable_bridge.dart';
import 'account_shell.dart';
import 'harness.dart';

NetworkInterfaceInfo _iface(String name, String ipv4,
        {bool vpn = false, bool defaultRoute = false}) =>
    NetworkInterfaceInfo(
      name: name,
      description: '',
      index: 0,
      ipv4: ipv4,
      isLoopback: false,
      isUp: true,
      isVirtual: vpn,
      isVpn: vpn,
      isDefaultRoute: defaultRoute,
    );

/// Marks the launch prompt as consumed so MoshApp mounts no overlay itself.
class _PromptConsumed extends FirstRunShown {
  @override
  bool build() => true;
}

/// A machine whose WireGuard tunnel owns the default route, with Wi-Fi
/// beside it, showing the consent modal over the chats.
Future<void> _consent(WidgetTester tester, Size size,
    {bool failSave = false}) async {
  late ScriptableBridge bridge;
  await pumpAccountApp(tester, size,
      overrides: [firstRunShownProvider.overrideWith(_PromptConsumed.new)],
      bridge: (gateway) {
    bridge = ScriptableBridge(conversations: gateway.conversations)
      ..seedVpnConsent(null)
      ..seedVpnDetection(const VpnDetection(
          vpnLikely: true,
          suspectInterfaces: ['wg0'],
          vpnOwnsDefaultRoute: true))
      ..seedInterfaces([
        _iface('wg0', '10.8.0.2', vpn: true, defaultRoute: true),
        _iface('wlan0', '192.168.1.24'),
      ]);
    if (failSave) {
      bridge.failAlways(BridgeMethod.setVpnBypassConsent,
          error: StateError('denied'));
    }
    return bridge;
  });
  tester.state<NavigatorState>(find.byType(Navigator).first).overlay!.insert(
      OverlayEntry(
          builder: (context) => VpnConsentModal(
              bridge: bridge,
              l: AppLocalizations.of(context)!,
              onAccept: () async {})));
  await tester.pumpAndSettle();
}

Future<void> _accept(WidgetTester tester) async {
  await tester.tap(find.text('Route around the VPN'));
  await tester.pumpAndSettle();
}

final List<FigmaScene> vpnScenes = [
  FigmaScene(
      'vpn-consent',
      'VPN / Consent / Asking',
      note: 'Mounted in the navigator overlay: in MoshApp the modal sits '
          'above the Navigator and fails to build its close tooltip.',
      (tester, size) => _consent(tester, size)),
  FigmaScene('vpn-consent-saving', 'VPN / Consent / Restarting',
      (tester, size) async {
    await _consent(tester, size);
    await _accept(tester);
  }),
  FigmaScene('vpn-consent-error', 'VPN / Consent / Save failed',
      (tester, size) async {
    await _consent(tester, size, failSave: true);
    await _accept(tester);
  }),
];
