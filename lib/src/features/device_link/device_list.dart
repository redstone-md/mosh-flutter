import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/device_link/types.dart';

class LinkedDeviceList extends StatelessWidget {
  const LinkedDeviceList({required this.snapshot, super.key});
  final DeviceLinkSnapshot snapshot;

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
              : null,
        ),
    ]);
  }
}
