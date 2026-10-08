import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'network_choice_provider.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';
import 'package:mosh/src/features/shared/mosh_dialog_motion.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/bypass_adapter.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;

/// The two phases the modal cycles through.
enum VpnConsentPhase { asking, saving }

/// The VPN-bypass consent modal.
///
/// Renders a scrim + dialog when it should ask, `SizedBox.shrink()`
/// otherwise. The host places it in a `Stack` overlay.
class VpnConsentModal extends ConsumerStatefulWidget {
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
  /// the app. Production wires the Windows-only desktop relauncher;
  /// unsupported platforms use a safe no-op. Failures are caught and
  /// shown by the modal.
  final Future<void> Function() onAccept;

  @override
  ConsumerState<VpnConsentModal> createState() => _VpnConsentModalState();
}

class _VpnConsentModalState extends ConsumerState<VpnConsentModal> {
  // Null = still loading the network state; '' = decided not to ask;
  // non-empty = the adapter to suggest.
  String? _adapter;
  bool _loading = true;
  VpnConsentPhase _phase = VpnConsentPhase.asking;
  String? _error;
  bool _retryRestart = false;

  @override
  void initState() {
    super.initState();
    _loadNetworkState();
  }

  // Fetch consent + detectVpn + listInterfaces, then only ask when the
  // tunnel owns the default route and consent is unset. A network
  // inventory we cannot read is not grounds for a blocking modal.
  Future<void> _loadNetworkState() async {
    String? adapter = '';
    try {
      final (saved, vpnOwnsDefaultRoute) = await ref
          .read(networkChoiceProvider(widget.bridge).notifier)
          .readPrompt();
      // Only ask when the tunnel actually carries Mosh's traffic.
      if (saved.adapter != null || !vpnOwnsDefaultRoute) {
        adapter = '';
      } else {
        final pick = defaultBypassAdapter(saved.interfaces);
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
      await ref
          .read(networkChoiceProvider(widget.bridge).notifier)
          .apply(_adapter, restart: widget.onAccept);
      // onAccept relaunches; if it returns (test), stay saving so the
      // dialog does not flicker back to asking.
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _phase = VpnConsentPhase.asking;
        _retryRestart = err is NetworkChoiceError &&
            err.kind == NetworkChoiceFailure.restart;
        _error = err is NetworkChoiceError &&
                err.kind == NetworkChoiceFailure.restart
            ? widget.l.bindAdapterRestartError
            : err is NetworkChoiceError && err.cause is Exception
                ? err.cause.toString()
                : widget.l.vpnConsentErrorFallback;
      });
    }
  }

  Future<void> _decline() async {
    if (_phase == VpnConsentPhase.saving ||
        ref.read(networkChoiceProvider(widget.bridge)).busy) {
      return;
    }
    setState(() => _phase = VpnConsentPhase.saving);
    try {
      await ref.read(networkChoiceProvider(widget.bridge).notifier).clear();
    } catch (_) {
      // A failed decline clear is not fatal; the modal still hides.
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
    final choice = ref.watch(networkChoiceProvider(widget.bridge));
    final visible = _shouldAsk &&
        !(choice.savedAdapter != null &&
            _phase == VpnConsentPhase.asking &&
            !_retryRestart);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : MoshDialogMotion.openDuration,
      reverseDuration: reduced ? Duration.zero : MoshDialogMotion.closeDuration,
      switchInCurve: MoshDialogMotion.curve,
      switchOutCurve: MoshDialogMotion.curve.flipped,
      transitionBuilder: _transition,
      child: visible
          ? _dialog(choice.busy)
          : const SizedBox.shrink(key: ValueKey('vpn-hidden')),
    );
  }

  Widget _transition(Widget child, Animation<double> animation) {
    if (child is SizedBox) return child;
    return Stack(children: [
      FadeTransition(
        opacity: animation,
        child: ModalBarrier(
          color: Colors.black54,
          dismissible: true,
          onDismiss: _decline,
          semanticsLabel: widget.l.dialogCancel,
        ),
      ),
      MoshDialogTransition(animation: animation, child: child),
    ]);
  }

  Widget _dialog(bool busy) {
    final l = widget.l;
    final saving = _phase == VpnConsentPhase.saving || busy;
    return MoshDialog(
      key: const ValueKey('vpn-consent'),
      title: l.vpnConsentTitle,
      closeLabel: l.dialogCancel,
      onCancel: _decline,
      canCancel: !saving,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.vpnConsentBody(_adapter!)),
          const SizedBox(height: 12),
          Text(l.vpnConsentCaveat),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Text(error,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : _decline,
          child: Text(l.vpnConsentDecline),
        ),
        FilledButton(
          onPressed: saving ? null : _accept,
          child: Text(saving ? l.vpnConsentAcceptSaving : l.vpnConsentAccept),
        ),
      ],
    );
  }
}
