import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/device_link/types.dart';

class LinkedDeviceList extends StatelessWidget {
  const LinkedDeviceList({required this.snapshot, this.onRemove, super.key});
  final DeviceLinkSnapshot snapshot;
  final ValueChanged<DeviceDescriptor>? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l.deviceLinkUserId, style: Theme.of(context).textTheme.labelLarge),
      SelectableText(snapshot.userId),
      const SizedBox(height: 16),
      for (final device in snapshot.devices)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.computer_outlined),
          title: Text(device.name),
          subtitle: SelectableText(device.deviceId),
          trailing: device.deviceId == snapshot.ownDeviceId
              ? Text(l.deviceLinkThisDevice)
              : onRemove == null
                  ? null
                  : IconButton(
                      tooltip: l.deviceLinkRemove,
                      onPressed: () => onRemove!(device),
                      icon: const Icon(Icons.link_off),
                    ),
        ),
      for (final status in snapshot.revocations)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.link_off),
          title: Text(status.device.name),
          subtitle: Text(status.state == DeviceRevocationState.pending
              ? l.deviceLinkRemovalPendingBody
              : l.deviceLinkRemovalAppliedBody),
          trailing: Text(status.state == DeviceRevocationState.pending
              ? l.deviceLinkRemovalPending
              : l.deviceLinkRemovalApplied),
        ),
    ]);
  }
}
