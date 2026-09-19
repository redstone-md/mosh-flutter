/// Diagnostics-drawer section widgets, 1-в-1 with React's
/// `src/features/private-dm/DiagnosticsDrawerSections.tsx`.
///
/// In scope (this atomic): the `SessionDiagnostics` "Conversation details"
/// group (the first group), the `MeshDiagnostics` "Moss network" group
/// (the second group), and the `EventLog` "Moss events" group (the third
/// group) -- so `SessionDiagnostics` now renders all three of React's
/// groups. Plus the shared primitives they need:
///   - `DiagnosticsGroup`  -- the `diagnostic-group` + `diagnostic-group-label`
///     shell (reused by `NoActiveSession` here, by `MeshDiagnostics`, and
///     by `EventLog`). Supports an optional `leading` icon widget for
///     group labels that start with an icon (e.g. `EventLog`'s activity
///     icon); existing callers pass no `leading` so they render unchanged.
///   - `DiagnosticsRow`     -- the `Row({ k, v })` primitive (a label span +
///     a strong value). Named `DiagnosticsRow` to avoid clashing with
///     Flutter's `Row`.
///   - `DiagnosticsEmptyState` -- the `.diagnostic-empty-state` body (a
///     bold title + a description span). Exposed (public) so both
///     `NoActiveSession` and `MeshDiagnostics`' "Mesh booting" state reuse
///     it (small DRY win).
///   - `NoActiveSession`    -- the React `NoActiveSession` (a `Session`
///     group with an empty-state).
///
/// `MeshDiagnostics` and `EventLog` live in their own files
/// (`mesh_diagnostics.dart` and `event_log.dart`) so this file stays
/// under 500 lines. The `ChannelDiagnostics` / `GroupDiagnostics`
/// sections now exist in `channel_group_diagnostics.dart` (their
/// `ChannelSnapshot` / `GroupSnapshot` contracts landed in b750a87).
/// `SessionDiagnostics` into `DiagnosticsScreen` is also a later atomic.
library;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/event_log.dart';
import 'package:mosh/src/features/diagnostics/mesh_diagnostics.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show MossLibraryInfo;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/util/format.dart';

/// The `diagnostic-group` shell: a bordered, rounded container with an
/// uppercase group-label header on a slightly different surface, then the
/// group's children in a column. Mirrors React's `.diagnostic-group` +
/// `.diagnostic-group-label` (middle-column.css): the group has a 1px line
/// border, 8px radius, and `overflow: hidden` so the label's bottom border
/// sits flush with the rows; the label is 9.5px, weight 700, uppercase, with
/// 0.08em letter-spacing, on the bg-1 surface with a bottom line.
///
/// Reusable by `SessionDiagnostics`, `NoActiveSession`, and the later
/// `MeshDiagnostics` / `EventLog` sections, so each section is the same shell
/// + a label + children.
class DiagnosticsGroup extends StatelessWidget {
  const DiagnosticsGroup({
    super.key,
    required this.label,
    this.leading,
    required this.children,
  });

  /// The uppercase group-label header text (already localized by the
  /// caller, e.g. `l.diagConversationDetails`).
  final String label;

  /// An optional widget rendered before the label text (e.g. an icon).
  /// React's `EventLog` label starts with an `IconActivity`; the other
  /// groups (Conversation details, Moss network, Session) have no icon,
  /// so they pass `null` (the default) and render unchanged.
  final Widget? leading;

  /// The group body (rows, an empty-state, a mesh grid, etc.).
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _GroupLabel(label: label, leading: leading),
          ...children,
        ],
      ),
    );
  }
}

/// The `.diagnostic-group-label` header: uppercase, weight 700, on the
/// bg-1 surface with a bottom line. Mirrors React's CSS (9.5px, 0.08em
/// letter-spacing, 6/10 padding, fg-3 color).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label, this.leading});

  final String label;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        // `.diagnostic-metric { background: var(--bg-1) }`.
        color: MoshColors.bg1,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              fontSize: 9.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The `Row({ k, v })` primitive -- a `.diagnostic-row`: a label span on the
/// left (fg-3) and a strong value on the right (fg-1, mono, right-aligned,
/// word-break). Mirrors React's `Row`. Named `DiagnosticsRow` to avoid
/// clashing with Flutter's `Row` widget.
///
/// Each row draws its own bottom divider (React's `.diagnostic-row` rule);
/// the group's `clipBehavior: Clip.antiAlias` + the label's bottom border
/// keep the visual seams clean, and the container's rounded clip hides the
/// last row's trailing line at the bottom edge, matching React's
/// `overflow: hidden`.
class DiagnosticsRow extends StatelessWidget {
  const DiagnosticsRow({super.key, required this.label, required this.value});

  /// The row key (`k` in React). Already localized by the caller.
  final String label;

  /// The row value (`v` in React). May be data (e.g. a transport-path
  /// label) or localized copy.
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The React `NoActiveSession`: a `Session` group with an empty-state
/// (a bold title + a description span). Mirrors React's
/// `.diagnostic-empty-state` (flex column, 4px gap, 13/10 padding, fg-3,
/// 11px / 1.4 line-height; the `strong` is fg-2, 11.5px, weight 700).
class NoActiveSession extends StatelessWidget {
  const NoActiveSession({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return DiagnosticsGroup(
      label: l.diagSessionLabel,
      children: [
        DiagnosticsEmptyState(
          title: l.diagNoActiveTitle,
          description: l.diagNoActiveBody,
        ),
      ],
    );
  }
}

/// The `.diagnostic-empty-state` body: a bold title + a description span.
/// Mirrors React's `.diagnostic-empty-state` (used by `NoActiveSession`
/// here, and by `MeshDiagnostics`' "Mesh booting" state; `EventLog`'s empty
/// state reuses it too). Public so the booting empty-state
/// shares the exact layout with the no-session empty-state (DRY).
class DiagnosticsEmptyState extends StatelessWidget {
  const DiagnosticsEmptyState({
    super.key,
    required this.title,
    required this.description,
  });

  /// The bold `strong` title (React: `fg-2`, 11.5px, weight 700).
  final String title;

  /// The description span (React: `fg-3`, 11px, 1.4 line-height).
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The React `SessionDiagnostics`: the "Conversation details" group (the
/// first group), the `MeshDiagnostics` "Moss network" group (the second
/// group), and the `EventLog` "Moss events" group (the third group).
/// Mirrors React's `SessionDiagnostics`, which renders three
/// `.diagnostic-group`s in that exact order: Conversation details, Moss
/// network, and EventLog. All three groups now render (1-в-1 with React).
///
/// Renders the first `.diagnostic-group` from React's `SessionDiagnostics`:
/// the "Conversation details" label, then the Peer / MLS state / Transport
/// / Peer id / Last connect / Role / Display / Session rows. The MLS-state
/// and Transport values come from `dm_state.dart`, the same wording the
/// header and the rail use, so "Connected" and "peer unknown" can never
/// appear together. The Session value uses `shorten(session.sessionId, 14)`
/// from `lib/src/util/format.dart`.
///
/// The second `.diagnostic-group` is the `MeshDiagnostics` "Moss network"
/// group (rendered below the Conversation-details group). The third is
/// `EventLog` (the "Moss events" group, rendered below Moss network) which
/// shows the last 40 session events newest-first, or the "No events yet"
/// empty-state. The session's `mesh` may be `null` (mesh still booting);
/// that case is handled by `MeshDiagnostics` itself (it renders the "Mesh
/// booting" empty-state).
class SessionDiagnostics extends StatelessWidget {
  const SessionDiagnostics({
    super.key,
    required this.session,
    this.libraryInfo,
  });

  final SessionSnapshot session;

  /// What the loaded moss library reports about itself (spec #5), read by
  /// the drawer and handed down; `null` keeps the group's library rows off
  /// the panel.
  final MossLibraryInfo? libraryInfo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final rows = <DiagnosticsRow>[
      DiagnosticsRow(
        label: l.diagRowPeer,
        value: session.peerDisplayName.isNotEmpty
            ? session.peerDisplayName
            : l.diagPeerUnknown,
      ),
      DiagnosticsRow(
        label: l.diagRowMlsState,
        value: dmStateLabel(l, session.state),
      ),
      DiagnosticsRow(
        label: l.diagRowTransport,
        value: transportLabel(l, session.transport),
      ),
      DiagnosticsRow(
        label: l.diagRowPeerId,
        value: session.peerMossId == null
            ? l.diagPeerIdUnknown
            : shorten(session.peerMossId!, 8),
      ),
      DiagnosticsRow(
        label: l.diagRowLastConnect,
        value: switch (session.lastConnectOutcome) {
          null => l.diagConnectNotYet,
          ConnectOutcome.requested => l.diagConnectRequested,
          ConnectOutcome.failed => l.diagConnectFailed,
        },
      ),
      DiagnosticsRow(label: l.diagRowRole, value: session.role),
      DiagnosticsRow(label: l.diagRowDisplay, value: session.displayName),
      DiagnosticsRow(
        label: l.diagSessionLabel,
        value: shorten(session.sessionId, 14),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DiagnosticsGroup(
          label: l.diagConversationDetails,
          children: rows,
        ),
        MeshDiagnostics(
          mesh: session.mesh,
          libraryInfo: libraryInfo,
          peerMossId: session.peerMossId,
        ),
        EventLog(events: session.events),
      ],
    );
  }
}
