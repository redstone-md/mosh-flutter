/// The `ChannelDiagnostics` and `GroupDiagnostics` sections (the second
/// and third `DiagnosticsDrawer` branches, alongside `SessionDiagnostics`).
///
/// The `ChannelSnapshot` / `GroupSnapshot` contracts landed in b750a87;
/// this file adds ONLY the two section widgets (plus their ARB keys).
/// Wiring them into the `PeerStatusDrawer` is a LATER atomic: the drawer
/// stays DM-only for now (there is no channel/group screen yet to host
/// the drawer with a channel/group).
///
/// In scope: `ChannelDiagnostics` (the "Channel details" group +
/// `MeshDiagnostics` + `EventLog`) and `GroupDiagnostics` (the "Group
/// details" group + `MeshDiagnostics` + `EventLog`). Reuses the shared
/// primitives `DiagnosticsGroup` / `DiagnosticsRow` (from
/// `diagnostics_sections.dart`), `MeshDiagnostics` (from
/// `mesh_diagnostics.dart`), `EventLog` (from `event_log.dart`),
/// `stateLabel` (from `state_label.dart`, for the group MLS state), and
/// `shorten` (from `lib/src/util/format.dart`). The
/// `diagRowDisplay` / `diagRowMlsState` ARB keys already exist and are
/// reused; the rest are added in this atomic.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/features/diagnostics/event_log.dart';
import 'package:mosh/src/features/diagnostics/mesh_diagnostics.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show MossLibraryInfo;
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/util/format.dart';

/// The "Channel details" group (4 rows: Name / Display / Topic / Device),
/// then `MeshDiagnostics`, then `EventLog`.
///   - Name    -> `#${channel.name}` (string concatenation, NOT localized;
///     the leading `#` is part of the value).
///   - Display -> `channel.display_name` (reuses the existing
///     `diagRowDisplay` row key).
///   - Topic   -> `channel.topic`.
///   - Device  -> `shorten(channel.device_fingerprint, 10)`.
///
/// The group label ("Channel details") and the four row keys are
/// localized (ARB). The Name value (`#...`) and the Topic / Device values
/// are DATA (not localized) -- the `#` prefix is a literal, not a
/// localized token. `mesh` may be `null` (handled by `MeshDiagnostics`);
/// `events` may be empty (handled by `EventLog`).
class ChannelDiagnostics extends StatelessWidget {
  const ChannelDiagnostics({
    super.key,
    required this.channel,
    this.libraryInfo,
  });

  final ChannelSnapshot channel;

  /// What the loaded moss library reports about itself (spec #5). A channel
  /// has no single counterpart, so its RTT row stays off; the version and
  /// field-log rows still render when the read is present.
  final MossLibraryInfo? libraryInfo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final rows = <DiagnosticsRow>[
      DiagnosticsRow(label: l.diagRowName, value: '#${channel.name}'),
      DiagnosticsRow(label: l.diagRowDisplay, value: channel.displayName),
      DiagnosticsRow(label: l.diagRowTopic, value: channel.topic),
      DiagnosticsRow(
        label: l.diagRowDevice,
        value: shorten(channel.deviceFingerprint, 10),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DiagnosticsGroup(label: l.diagGroupChannelDetails, children: rows),
        MeshDiagnostics(mesh: channel.mesh, libraryInfo: libraryInfo),
        EventLog(events: channel.events),
      ],
    );
  }
}

/// The "Group details" group (8 rows: Label / Members / Role / MLS state /
/// Display / Group id / Creator / Device), then `MeshDiagnostics`, then
/// `EventLog`:
///   - Label     -> `group.label ?? "-"` (the `-` is the localized
///     `diagDash` fallback for a null label).
///   - Members   -> `group.memberCount.toString()` (`memberCount` is a
///     `BigInt`).
///   - Role      -> `group.is_admin ? "admin" : "member"` (the two
///     values are localized via `diagRoleAdmin` / `diagRoleMember`).
///   - MLS state -> the shared `stateLabel` mapper (reuses the existing
///     `diagRowMlsState` row key, just like `SessionDiagnostics` does).
///   - Display   -> `group.display_name` (reuses `diagRowDisplay`).
///   - Group id  -> `shorten(group.group_id, 12)`.
///   - Creator   -> `shorten(group.creator_fingerprint, 8)`.
///   - Device    -> `shorten(group.device_fingerprint, 10)`.
///
/// The group label ("Group details") and the eight row keys are
/// localized (ARB). The Members / Group id / Creator / Device values are
/// DATA (not localized). `mesh` may be `null` (handled by
/// `MeshDiagnostics`); `events` may be empty (handled by `EventLog`).
class GroupDiagnostics extends StatelessWidget {
  const GroupDiagnostics({
    super.key,
    required this.group,
    this.libraryInfo,
  });

  final GroupSnapshot group;

  /// What the loaded moss library reports about itself (spec #5). A group
  /// has no single counterpart, so its RTT row stays off; the version and
  /// field-log rows render when the read is present.
  final MossLibraryInfo? libraryInfo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final rows = <DiagnosticsRow>[
      DiagnosticsRow(
        label: l.diagRowLabel,
        value: group.label ?? l.diagDash,
      ),
      DiagnosticsRow(
        label: l.diagRowMembers,
        value: group.memberCount.toString(),
      ),
      DiagnosticsRow(
        label: l.diagRowRole,
        value: group.isAdmin ? l.diagRoleAdmin : l.diagRoleMember,
      ),
      DiagnosticsRow(
        label: l.diagRowMlsState,
        value: stateLabel(l, group.state),
      ),
      DiagnosticsRow(label: l.diagRowDisplay, value: group.displayName),
      DiagnosticsRow(
        label: l.diagRowGroupId,
        value: shorten(group.groupId, 12),
      ),
      DiagnosticsRow(
        label: l.diagRowCreator,
        value: shorten(group.creatorFingerprint, 8),
      ),
      DiagnosticsRow(
        label: l.diagRowDevice,
        value: shorten(group.deviceFingerprint, 10),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DiagnosticsGroup(label: l.diagGroupGroupDetails, children: rows),
        MeshDiagnostics(mesh: group.mesh, libraryInfo: libraryInfo),
        EventLog(events: group.events),
      ],
    );
  }
}
