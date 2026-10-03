import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'network_choice_provider.dart';

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
    if (!_shouldAsk ||
        choice.savedAdapter != null &&
            _phase == VpnConsentPhase.asking &&
            !_retryRestart) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final danger = const Color(0xFFE5484D);
    final saving = _phase == VpnConsentPhase.saving || choice.busy;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dark scrim. (A blur is omitted -- Flutter BackdropFilter is
          // expensive + not critical for the dialog's affordance.)
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
                      // Warning icon (22, danger tint).
                      Icon(Icons.warning, size: 22, color: danger),
                      const SizedBox(height: 10),
                      Text(
                        widget.l.vpnConsentTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      // Body text (with the adapter name).
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
                      // Caveat text.
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
                      // Right-aligned action row (decline + accept).
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            // Decline (ghost).
                            TextButton(
                              onPressed: saving ? null : _decline,
                              child: Text(widget.l.vpnConsentDecline),
                            ),
                            // Accept (primary).
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
