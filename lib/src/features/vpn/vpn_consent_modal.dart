// VpnConsentModal -- 1-в-1 port of React `src/features/private-dm/vpn/
// VpnConsentModal.tsx`. The one question Mosh asks about the VPN, shown
// when the user has not answered AND a VPN owns the default route. It
// blocks because the answer cannot be applied later: a node's bind
// interface is fixed when the node is built, so a setting flipped
// mid-session changes nothing until the next launch. Saying yes
// (accept) records the consent + relaunches; saying no (decline) records
// nothing (a refusal is asked again next launch -- a wrong yes is
// visible + reversible from advanced settings, a remembered no silently
// strands someone whose network changed).
//
// React structure (VpnConsentModal.tsx):
//   .vpn-consent-scrim (fixed inset-0, rgba(0,0,0,0.55) + blur(3))
//     -> .vpn-consent (role=alertdialog, aria-modal, aria-labelledby,
//        aria-describedby, 440px max, danger border tint, 14 radius)
//        -> span.vpn-consent-icon (IconAlertTriangle 22, danger tint)
//        -> h2#vpn-consent-title
//        -> p#vpn-consent-body (with <code>{adapter}</code>)
//        -> p.vpn-consent-caveat
//        -> p.vpn-consent-error (if error)
//        -> .vpn-consent-actions (flex, gap 8, end)
//           -> btn-ghost decline ("Keep using the VPN")
//           -> btn-primary accept ("Route around the VPN" / "Restarting...")
//
// On mount React `Promise.all([getVpnBypassConsent, detectVpn,
// listNetworkInterfaces])` -- only ask when `!consent && detection
// .vpn_owns_default_route`; pick `defaultBypassAdapter(interfaces)`.
// Accept: `setVpnBypassConsent(adapter)` + `restartApp()`. Decline:
// `setVpnBypassConsent(null)` (clears any prior answer) then hide.
//
// Flutter port: a `StatefulWidget` that fetches the network state in
// `initState`, renders a scrim `Stack` overlay + a danger-tinted `Dialog`
// when it should ask, and `SizedBox.shrink()` otherwise (the host places
// it in a `Stack`; React renders the scrim inline as `position: fixed`).
// `restartApp` is an injectable callback (`onAccept`) so the modal remains
// parity-first and testable. Production supplies the Windows-only desktop
// relauncher; unsupported platforms use its safe no-op behavior. The dialog mirrors React's
// danger tint (`--danger` #e5484d border + icon) + the 440px max width.

library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/bypass_adapter.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/rust/api/vpn.dart' show VpnDetection;
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;
import 'package:mosh/src/rust/vpn_consent.dart' show VpnBypassConsent;

/// The two phases the modal cycles through (React `Answer`).
enum VpnConsentPhase { asking, saving }

/// The VPN-bypass consent modal -- 1-в-1 with React's `VpnConsentModal`.
///
/// Renders a scrim + dialog when it should ask, `SizedBox.shrink()`
/// otherwise. The host places it in a `Stack` overlay.
class VpnConsentModal extends StatefulWidget {
  const VpnConsentModal({
    super.key,
    required this.bridge,
    required this.l,
    required this.onAccept,
  });

  /// The bridge facade (getVpnBypassConsent/detectVpn/listInterfaces/
  /// setVpnBypassConsent). Injected so tests can pass a scripted double.
  final BridgeFacade bridge;

  /// Localizations (vpnConsentTitle / vpnConsentBody / vpnConsentCaveat /
  /// vpnConsentDecline / vpnConsentAccept / vpnConsentAcceptSaving /
  /// vpnConsentErrorFallback).
  final AppLocalizations l;

  /// Invoked after `setVpnBypassConsent(adapter)` succeeds, to relaunch
  /// the app (React `gateway.restartApp()`). Production wires the
  /// Windows-only desktop relauncher; unsupported platforms use a safe
  /// no-op. Failures are caught and shown by the modal.
  final Future<void> Function() onAccept;

  @override
  State<VpnConsentModal> createState() => _VpnConsentModalState();
}

class _VpnConsentModalState extends State<VpnConsentModal> {
  // Null = still loading the network state; '' = decided not to ask;
  // non-empty = the adapter to suggest.
  String? _adapter;
  bool _loading = true;
  VpnConsentPhase _phase = VpnConsentPhase.asking;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNetworkState();
  }

  // React: `Promise.all([getVpnBypassConsent, detectVpn, listInterfaces])`
  // then `if (consent || !detection.vpn_owns_default_route) return;` +
  // `defaultBypassAdapter(interfaces)`. A network inventory we cannot
  // read is not grounds for a blocking modal (React warns + returns).
  Future<void> _loadNetworkState() async {
    String? adapter = '';
    try {
      final results = await Future.wait([
        widget.bridge.getVpnBypassConsent(),
        widget.bridge.detectVpn(),
        widget.bridge.listInterfaces(),
      ]);
      final consent = results[0] as VpnBypassConsent?;
      final detection = results[1] as VpnDetection;
      final interfaces = results[2] as List<NetworkInterfaceInfo>;
      // Only ask when the tunnel actually carries Mosh's traffic.
      if (consent != null || !detection.vpnOwnsDefaultRoute) {
        adapter = '';
      } else {
        final pick = defaultBypassAdapter(interfaces);
        adapter = pick.isEmpty ? '' : pick;
      }
    } catch (_) {
      // A network inventory we cannot read is not grounds for a blocking
      // modal; the app opens and advanced settings still work.
      adapter = '';
    }
    if (!mounted) return;
    setState(() {
      _adapter = adapter;
      _loading = false;
    });
  }

  Future<void> _accept() async {
    setState(() {
      _phase = VpnConsentPhase.saving;
      _error = null;
    });
    try {
      await widget.bridge.setVpnBypassConsent(interfaceName: _adapter);
      await widget.onAccept();
      // onAccept relaunches; if it returns (test), stay saving so the
      // dialog does not flicker back to asking.
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _phase = VpnConsentPhase.asking;
        _error = err is Exception
            ? err.toString()
            : widget.l.vpnConsentErrorFallback;
      });
    }
  }

  Future<void> _decline() async {
    setState(() => _phase = VpnConsentPhase.saving);
    try {
      await widget.bridge.setVpnBypassConsent(interfaceName: null);
    } catch (_) {
      // React warns on a failed decline clear; the modal still hides.
    }
    if (!mounted) return;
    setState(() => _adapter = '');
  }

  bool get _shouldAsk {
    final a = _adapter;
    return !_loading && a != null && a.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldAsk) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final danger = const Color(0xFFE5484D);
    final saving = _phase == VpnConsentPhase.saving;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // .vpn-consent-scrim: rgba(0,0,0,0.55). (blur(3px) is omitted --
          // Flutter BackdropFilter is expensive + not parity-critical
          // for the dialog's affordance.)
          const ModalBarrier(
            color: Color(0x8C000000),
            dismissible: false,
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Dialog(
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                backgroundColor: theme.colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // .vpn-consent-icon (IconAlertTriangle 22, danger).
                      Icon(Icons.warning, size: 22, color: danger),
                      const SizedBox(height: 10),
                      // h2#vpn-consent-title.
                      Text(
                        widget.l.vpnConsentTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      // p#vpn-consent-body (with <code>{adapter}</code>).
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: widget.l.vpnConsentBody(_adapter!),
                            ),
                          ],
                        ),
                        style:
                            theme.textTheme.bodySmall?.copyWith(height: 1.45),
                      ),
                      const SizedBox(height: 10),
                      // p.vpn-consent-caveat.
                      Text(
                        widget.l.vpnConsentCaveat,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          height: 1.4,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: danger, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // .vpn-consent-actions (end, gap 8, wrap).
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            // btn-ghost decline.
                            TextButton(
                              onPressed: saving ? null : _decline,
                              child: Text(widget.l.vpnConsentDecline),
                            ),
                            // btn-primary accept.
                            FilledButton(
                              onPressed: saving ? null : _accept,
                              child: Text(
                                saving
                                    ? widget.l.vpnConsentAcceptSaving
                                    : widget.l.vpnConsentAccept,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
