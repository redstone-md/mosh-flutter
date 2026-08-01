/// The React `ChannelDiagnostics` and `GroupDiagnostics` sections, 1-in-1
/// with `src/features/private-dm/DiagnosticsDrawerSections.tsx` (the
/// second and third `DiagnosticsDrawer` branches, alongside
/// `SessionDiagnostics`).
///
/// These were previously DEFERRED because the `ChannelSnapshot` /
/// `GroupSnapshot` contracts did not exist in the Flutter fork. They now
/// do -- the channels/groups read seam landed in b750a87 -- so this
/// atomic adds ONLY the two section widgets (plus their ARB keys). Wiring
/// them into the `PeerStatusDrawer` is a LATER atomic: the drawer stays
/// DM-only for now (there is no channel/group screen yet to host the
/// drawer with a channel/group).
///
/// In scope (this atomic): `ChannelDiagnostics` (the "Channel details"
/// `.diagnostic-group` + `MeshDiagnostics` + `EventLog`) and
/// `GroupDiagnostics` (the "Group details" `.diagnostic-group` +
/// `MeshDiagnostics` + `EventLog`). Each mirrors the exact React row
/// order + values. Reuses the shared primitives `DiagnosticsGroup` /
/// `DiagnosticsRow` (from `diagnostics_sections.dart`), `MeshDiagnostics`
/// (from `mesh_diagnostics.dart`), `EventLog` (from `event_log.dart`),
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
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/util/format.dart';

/// The React `ChannelDiagnostics`: the "Channel details"
/// `.diagnostic-group` (4 rows: Name / Display / Topic / Device), then
/// `MeshDiagnostics`, then `EventLog`. Mirrors React's
/// `ChannelDiagnostics({ channel })` exactly:
///   - Name    -> `#${channel.name}` (string concatenation, NOT localized;
///     the leading `#` is part of the value, matching React's template
///     literal `` `#${channel.name}` ``).
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
  const ChannelDiagnostics({super.key, required this.channel});

  final ChannelSnapshot channel;

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
        MeshDiagnostics(mesh: channel.mesh),
        EventLog(events: channel.events),
      ],
    );
  }
}

/// The React `GroupDiagnostics`: the "Group details" `.diagnostic-group`
/// (8 rows: Label / Members / Role / MLS state / Display / Group id /
/// Creator / Device), then `MeshDiagnostics`, then `EventLog`. Mirrors
/// React's `GroupDiagnostics({ group })` exactly:
///   - Label     -> `group.label ?? "-"` (the `-` is the localized
///     `diagDash` fallback for a null label; React uses the literal `-`).
///   - Members   -> `String(group.member_count)` (Dart:
///     `group.memberCount.toString()` -- `memberCount` is a `BigInt`).
///   - Role      -> `group.is_admin ? "admin" : "member"` (the two
///     values are localized via `diagRoleAdmin` / `diagRoleMember`).
///   - MLS state -> `stateLabels[group.state] ?? group.state` (reuses
///     the shared `stateLabel` mapper and the existing `diagRowMlsState`
///     row key, just like `SessionDiagnostics` does).
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
  const GroupDiagnostics({super.key, required this.group});

  final GroupSnapshot group;

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
        MeshDiagnostics(mesh: group.mesh),
        EventLog(events: group.events),
      ],
    );
  }
}
