import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/settings_card.dart';
import 'package:mosh/src/rust/device_link/types.dart';
import 'package:mosh/src/util/format.dart';

class LinkedDeviceList extends StatelessWidget {
  const LinkedDeviceList({required this.snapshot, this.onRemove, super.key});
  final DeviceLinkSnapshot snapshot;
  final ValueChanged<DeviceDescriptor>? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsCard(
          icon: Icons.people_outline,
          title: l.deviceLinkUserId,
          hint: l.deviceLinkDevicesHint,
          child: _Id(snapshot.userId)),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: MoshColors.bg1,
          borderRadius: MoshShapes.composer,
          border: Border.all(color: MoshColors.line),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
              header: true,
              child: Text(l.deviceLinkDevicesTitle,
                  style: Theme.of(context).textTheme.titleMedium)),
          for (final device in snapshot.devices)
            _DeviceRow(
                device: device,
                own: device.deviceId == snapshot.ownDeviceId,
                onRemove: onRemove),
          for (final status in snapshot.revocations)
            _RevocationRow(status: status),
        ]),
      ),
    ]);
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow(
      {required this.device, required this.own, required this.onRemove});
  final DeviceDescriptor device;
  final bool own;
  final ValueChanged<DeviceDescriptor>? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MoshColors.bg2,
        borderRadius: MoshShapes.conversationRow,
        border: Border.all(color: MoshColors.line),
      ),
      child: Row(children: [
        const Icon(Icons.devices_outlined, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(device.name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            _Id(device.deviceId),
            if (own) ...[
              const SizedBox(height: 6),
              Text(l.deviceLinkThisDevice,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: MoshColors.moss)),
            ],
          ]),
        ),
        if (!own && onRemove != null)
          IconButton(
              tooltip: l.deviceLinkRemove,
              onPressed: () => onRemove!(device),
              icon: const Icon(Icons.link_off, size: 20)),
      ]),
    );
  }
}

class _RevocationRow extends StatelessWidget {
  const _RevocationRow({required this.status});
  final DeviceRevocationStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final pending = status.state == DeviceRevocationState.pending;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(status.device.name, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(pending ? l.deviceLinkRemovalPending : l.deviceLinkRemovalApplied),
        const SizedBox(height: 4),
        Text(
            pending
                ? l.deviceLinkRemovalPendingBody
                : l.deviceLinkRemovalAppliedBody,
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

/// Linking uses QR and code; these ids are only for comparison by eye.
class _Id extends StatelessWidget {
  const _Id(this.id);
  final String id;

  @override
  Widget build(BuildContext context) =>
      Text(shorten(id, 8), style: const TextStyle(fontFamily: 'monospace'));
}
