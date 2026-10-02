import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_select.dart';
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
          if (candidates.isEmpty)
            Text(l.bindAdapterNoNic, style: text.bodySmall),
          if (candidates.isNotEmpty || current != null) _controls(candidates),
          if (error != null) ...[
            const SizedBox(height: 12),
            Semantics(
                liveRegion: true,
                child: Text(error!,
                    style: text.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error))),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  visualDensity: VisualDensity.standard),
              onPressed: busy ? null : onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l.settingsRefreshDevices),
            ),
          ),
        ],
        const SizedBox(height: 8),
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

  Widget _controls(List<NetworkInterfaceInfo> candidates) {
    const style = ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, 44)),
        visualDensity: VisualDensity.standard);
    final missing =
        current != null && !candidates.any((iface) => iface.name == current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MoshSelect<String>(
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
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: current != null
              ? TextButton(
                  style: style,
                  onPressed: busy ? null : onApply,
                  child:
                      Text(busy ? l.bindAdapterSaving : l.bindAdapterRelease))
              : FilledButton(
                  style: style,
                  onPressed: busy || picked.isEmpty ? null : onApply,
                  child: Text(busy ? l.bindAdapterSaving : l.bindAdapterBind)),
        ),
      ],
    );
  }
}
