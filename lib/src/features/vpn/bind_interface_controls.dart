import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/app/mosh_switch.dart';
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
    required this.stateKnown,
    required this.busy,
    required this.error,
    required this.needsRestart,
    required this.canRelaunch,
    required this.onPick,
    required this.onToggle,
    required this.onRefresh,
  });

  final AppLocalizations l;
  final List<NetworkInterfaceInfo> interfaces;
  final String? current;
  final String picked;
  final bool loading;
  final bool stateKnown;
  final bool busy;
  final String? error;
  final bool needsRestart;
  final bool canRelaunch;
  final ValueChanged<String> onPick;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final candidates = bypassCandidates(interfaces);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toggle(),
        if (stateKnown) ...[
          const SizedBox(height: 16),
          Text(
              current == null
                  ? l.bindAdapterUnboundBody
                  : l.bindAdapterBoundBody(current!),
              style: text.bodyMedium),
        ],
        if (!loading || stateKnown || error != null) ...[
          const SizedBox(height: 16),
          if (stateKnown)
            _pickerRow(context, candidates)
          else
            Align(
                alignment: AlignmentDirectional.centerStart,
                child: _refresh(MoshColors.of(context))),
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

  Widget _toggle() => MoshSwitchRow(
        title: l.bindAdapterToggle,
        subtitle: _status(),
        value: current != null,
        saving: busy,
        onChanged: !stateKnown || loading || (current == null && picked.isEmpty)
            ? null
            : onToggle,
      );

  String _status() {
    if (loading) return l.settingsDevicesLoading;
    if (!stateKnown) return l.bindAdapterUnknown;
    if (busy) return l.bindAdapterSaving;
    return current != null ? l.bindAdapterEnabled : l.bindAdapterDisabled;
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
        _refresh(MoshColors.of(context)),
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
      onChanged: loading || busy || current != null ? null : onPick,
    );
  }

  Widget _refresh(MoshColors colors) => IconButton(
        tooltip: l.settingsRefreshDevices,
        onPressed: loading || busy ? null : onRefresh,
        icon: const Icon(MoshIcons.refresh, size: 20),
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          visualDensity: VisualDensity.standard,
          foregroundColor: colors.onSurfaceVariant,
        ),
      );
}
