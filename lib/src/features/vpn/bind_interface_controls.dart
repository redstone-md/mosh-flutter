import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/rust/network_inventory.dart';

import 'bypass_adapter.dart';

/// Responsive form for the saved override, separate from async persistence.
class BindInterfaceControls extends StatelessWidget {
  const BindInterfaceControls({
    super.key,
    required this.l,
    required this.interfaces,
    required this.current,
    required this.picked,
    required this.loading,
    required this.busy,
    required this.error,
    required this.needsRestart,
    required this.canRelaunch,
    required this.onPick,
    required this.onApply,
    required this.onRefresh,
  });

  final AppLocalizations l;
  final List<NetworkInterfaceInfo> interfaces;
  final String? current;
  final String picked;
  final bool loading;
  final bool busy;
  final String? error;
  final bool needsRestart;
  final bool canRelaunch;
  final ValueChanged<String> onPick;
  final VoidCallback onApply;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final candidates = bypassCandidates(interfaces);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            current == null
                ? l.bindAdapterUnboundBody
                : l.bindAdapterBoundBody(current!),
            style: text.bodyMedium),
        const SizedBox(height: 16),
        if (loading)
          Text(l.settingsDevicesLoading, style: text.bodySmall)
        else ...[
          _pickerRow(context, candidates),
          if (candidates.isNotEmpty || current != null) ...[
            const SizedBox(height: 12),
            Align(
                alignment: AlignmentDirectional.centerStart, child: _action()),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Semantics(
                liveRegion: true,
                child: Text(error!,
                    style: text.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error))),
          ],
        ],
        const SizedBox(height: 16),
        Text(l.bindAdapterHint, style: text.bodySmall),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: needsRestart,
          child: Text(
              needsRestart
                  ? l.bindAdapterRestartNeeded
                  : canRelaunch
                      ? l.bindAdapterAutoRestart
                      : l.bindAdapterManualRestart,
              style: text.bodySmall),
        ),
      ],
    );
  }

  Widget _pickerRow(
          BuildContext context, List<NetworkInterfaceInfo> candidates) =>
      Row(children: [
        Expanded(
            child: candidates.isEmpty && current == null
                ? Text(l.bindAdapterNoNic,
                    style: Theme.of(context).textTheme.bodySmall)
                : _selector(candidates)),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l.settingsRefreshDevices,
          onPressed: busy ? null : onRefresh,
          icon: const Icon(Icons.refresh, size: 20),
          style: IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            visualDensity: VisualDensity.standard,
            foregroundColor: MoshColors.fg2,
          ),
        ),
      ]);

  Widget _selector(List<NetworkInterfaceInfo> candidates) {
    final missing =
        current != null && !candidates.any((iface) => iface.name == current);
    return MoshSelect<String>(
      label: l.bindAdapterTitle,
      value: current ?? picked,
      options: [
        if (missing)
          MoshSelectOption(current!, l.bindAdapterUnavailable(current!),
              enabled: false),
        for (final iface in candidates)
          MoshSelectOption(iface.name, adapterLabel(iface)),
      ],
      onChanged: busy || current != null ? null : onPick,
    );
  }

  Widget _action() => OutlinedButton(
        onPressed: busy || (current == null && picked.isEmpty) ? null : onApply,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          visualDensity: VisualDensity.standard,
          foregroundColor: MoshColors.fg1,
        ),
        child: Text(busy
            ? l.bindAdapterSaving
            : current != null
                ? l.bindAdapterRelease
                : l.bindAdapterBind),
      );
}
