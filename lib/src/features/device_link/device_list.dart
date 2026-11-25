import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/settings_card.dart';
import 'package:mosh/src/rust/device_link/types.dart';
import 'package:mosh/src/util/format.dart';

/// The devices of one user: their id in a card of its own, then every device
/// as a [_DeviceRow] and every removal as a note under the list.
class LinkedDeviceList extends StatelessWidget {
  const LinkedDeviceList({required this.snapshot, this.onRemove, super.key});
  final DeviceLinkSnapshot snapshot;
  final ValueChanged<DeviceDescriptor>? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsCard(
          icon: MoshIcons.group,
          title: l.deviceLinkUserId,
          hint: l.deviceLinkDevicesHint,
          child: _Id(snapshot.userId)),
      const SizedBox(height: MoshSpace.s4),
      SettingsSurface(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
              header: true,
              child: Text(l.deviceLinkDevicesTitle,
                  style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(height: MoshSpace.s1),
          for (final device in snapshot.devices)
            _DeviceRow(
                name: device.name,
                id: device.deviceId,
                notes: [
                  if (device.deviceId == snapshot.ownDeviceId)
                    l.deviceLinkThisDevice
                ],
                onRemove:
                    device.deviceId == snapshot.ownDeviceId || onRemove == null
                        ? null
                        : () => onRemove!(device)),
          for (final status in snapshot.revocations)
            _DeviceRow.removal(
                name: status.device.name,
                id: status.device.deviceId,
                applied: status.state != DeviceRevocationState.pending,
                notes: status.state == DeviceRevocationState.pending
                    ? [
                        l.deviceLinkRemovalPending,
                        l.deviceLinkRemovalPendingBody
                      ]
                    : [
                        l.deviceLinkRemovalApplied,
                        l.deviceLinkRemovalAppliedBody
                      ]),
        ]),
      ),
    ]);
  }
}

/// The Device row card. A device stands on a plate: this one says so in the
/// accent, another can be removed. A removal is a status about a device that
/// is leaving or gone, so it is the same row without the plate and without
/// the action: it reads as a note under the list, faded once [applied].
class _DeviceRow extends StatelessWidget {
  const _DeviceRow(
      {required this.name,
      required this.id,
      required this.notes,
      this.onRemove})
      : removal = false,
        applied = false;

  const _DeviceRow.removal(
      {required this.name,
      required this.id,
      required this.notes,
      required this.applied})
      : removal = true,
        onRemove = null;

  final String name;
  final String id;

  /// What is said under the id, a line each.
  final List<String> notes;
  final VoidCallback? onRemove;
  final bool removal;
  final bool applied;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final text = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;
    Color faded(Color ink) =>
        applied ? MoshState.tint(ink, MoshState.disabledContent) : ink;
    return Container(
      margin: const EdgeInsets.only(top: MoshSpace.s2),
      constraints: const BoxConstraints(minHeight: MoshSpace.s16),
      padding: EdgeInsetsDirectional.fromSTEB(MoshSpace.s4, MoshSpace.s2,
          onRemove == null ? MoshSpace.s4 : MoshSpace.s1, MoshSpace.s2),
      decoration: removal
          ? null
          : BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius:
                  const BorderRadius.all(Radius.circular(MoshRadius.small))),
      child: Row(children: [
        Icon(removal ? MoshIcons.linkOff : MoshIcons.devices,
            size: MoshSpace.s5, color: faded(colors.onSurfaceVariant)),
        const SizedBox(width: MoshSpace.s3),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    text.titleSmall!.copyWith(color: faded(colors.onSurface))),
            _Id(id),
            for (final words in notes)
              Text(words,
                  style: text.bodySmall!.copyWith(
                      color:
                          removal ? colors.onSurfaceVariant : colors.primary)),
          ]),
        ),
        if (onRemove != null)
          IconButton(
              tooltip: l.deviceLinkRemove,
              onPressed: onRemove,
              icon: const Icon(MoshIcons.linkOff)),
      ]),
    );
  }
}

/// Linking uses QR and code; these ids are only for comparison by eye.
class _Id extends StatelessWidget {
  const _Id(this.id);
  final String id;

  @override
  Widget build(BuildContext context) => Text(shorten(id, 8),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context)
          .textTheme
          .bodySmall!
          .copyWith(color: MoshColors.of(context).onSurfaceMuted));
}
