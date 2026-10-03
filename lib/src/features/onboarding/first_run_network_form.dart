import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/vpn/bypass_adapter.dart';
import 'package:mosh/src/features/vpn/network_choice_provider.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import 'first_run_network_provider.dart';
import 'first_run_profile.dart';
import 'first_run_provider.dart';

class FirstRunNetworkForm extends ConsumerStatefulWidget {
  const FirstRunNetworkForm({super.key, required this.network});
  final SetupNetwork network;

  @override
  ConsumerState<FirstRunNetworkForm> createState() =>
      _FirstRunNetworkFormState();
}

class _FirstRunNetworkFormState extends ConsumerState<FirstRunNetworkForm> {
  late String? _picked = widget.network.savedAdapter;
  bool _busy = false;
  String? _error;

  bool get _needsRestart => ref
      .read(networkChoiceProvider(ref.read(bridgeFacadeProvider)).notifier)
      .requiresRestart(_picked);

  bool get _saving =>
      _busy ||
      ref.read(networkChoiceProvider(ref.read(bridgeFacadeProvider))).busy;

  bool get _selectionAvailable =>
      _picked == null ||
      bypassCandidates(widget.network.interfaces)
          .any((adapter) => adapter.name == _picked);

  Future<void> _finish() async {
    if (_saving || !_selectionAvailable) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(networkChoiceProvider(ref.read(bridgeFacadeProvider)).notifier)
          .apply(_picked, complete: (restart) async {
        if (!mounted) return;
        await ref.read(firstRunProfileProvider.notifier).finish(restart);
      }, restart: () async {
        if (!mounted) return;
        final relauncher = DesktopAppRelauncherScope.of(context);
        if (relauncher.supported) {
          await relauncher.relaunch();
        } else {
          await _manualRestart();
        }
      });
    } on NetworkChoiceError catch (error) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        setState(() => _error = error.kind == NetworkChoiceFailure.restart
            ? l.firstRunRestartError
            : l.firstRunSaveError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manualRestart() async {
    final l = AppLocalizations.of(context)!;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
              title: Text(l.firstRunRestartTitle),
              content: Text(l.firstRunManualRestart),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.firstRunUnderstood))
              ],
            ));
  }

  Future<void> _back() async {
    try {
      await ref.read(firstRunProfileProvider.notifier).goTo(SetupStep.device);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = AppLocalizations.of(context)!.firstRunSaveError);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(networkChoiceProvider(ref.watch(bridgeFacadeProvider)));
    final l = AppLocalizations.of(context)!;
    final relauncher = DesktopAppRelauncherScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.network.vpnDetected) ...[
        Text(l.firstRunVpnDetected,
            style: const TextStyle(color: MoshColors.warn)),
        const SizedBox(height: 16),
      ],
      _picker(l),
      const SizedBox(height: 16),
      Text(_picked == null ? l.firstRunAutomaticHint : l.firstRunBypassHint,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: MoshColors.fg2)),
      if (_needsRestart) ...[
        const SizedBox(height: 12),
        Text(l.bindAdapterRestartNeeded),
      ],
      const SizedBox(height: 28),
      FilledButton(
          onPressed: _saving || !_selectionAvailable ? null : _finish,
          child: Text(_saving
              ? l.firstRunSaving
              : _needsRestart && relauncher.supported
                  ? l.firstRunSaveRestart
                  : l.firstRunFinish)),
      const SizedBox(height: 12),
      TextButton(
          onPressed: _saving ? null : _back, child: Text(l.firstRunBack)),
      if (_error != null)
        Semantics(
            liveRegion: true,
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ]);
  }

  Widget _picker(AppLocalizations l) {
    final candidates = bypassCandidates(widget.network.interfaces);
    final missing = _picked != null &&
        !candidates.any((adapter) => adapter.name == _picked);
    return MoshSelect<String?>(
        label: l.firstRunNetworkAdapter,
        value: _picked,
        options: [
          MoshSelectOption(null, l.firstRunAutomatic),
          for (final adapter in candidates)
            MoshSelectOption(adapter.name, adapterLabel(adapter)),
          if (missing)
            MoshSelectOption(_picked, l.firstRunAdapterUnavailable(_picked!),
                enabled: false),
        ],
        onChanged:
            _saving ? null : (adapter) => setState(() => _picked = adapter));
  }
}
