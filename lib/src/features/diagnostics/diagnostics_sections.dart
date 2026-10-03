import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/event_log.dart';
import 'package:mosh/src/features/diagnostics/mesh_diagnostics.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show MossLibraryInfo;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';
import 'package:mosh/src/util/format.dart';

/// A bordered, rounded group shell with an uppercase label header, then
/// the group's children in a column.
///
/// Reusable by `SessionDiagnostics`, `NoActiveSession`,
/// `MeshDiagnostics`, and `EventLog`, so each section is the same shell
/// + a label + children.
class DiagnosticsGroup extends StatelessWidget {
  const DiagnosticsGroup({
    super.key,
    required this.label,
    this.leading,
    this.children = const [],
    this.rows = const [],
  });

  /// The uppercase group-label header text (already localized by the
  /// caller, e.g. `l.diagConversationDetails`).
  final String label;

  /// An optional widget rendered before the label text (e.g. an icon).
  final Widget? leading;

  /// The group body (rows, an empty-state, a mesh grid, etc.).
  final List<Widget> children;
  final List<(String, String)> rows;

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
          for (final (label, value) in rows)
            DiagnosticsRow(label: label, value: value),
        ],
      ),
    );
  }
}

/// The group-label header: uppercase, bold, on a tinted surface with a
/// bottom line.
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

/// A key/value row: a muted label on the left and a mono, right-aligned
/// value on the right. Named `DiagnosticsRow` to avoid clashing with
/// Flutter's `Row` widget.
///
/// Each row draws its own bottom divider; the group's
/// `clipBehavior: Clip.antiAlias` + the label's bottom border keep the
/// visual seams clean, and the container's rounded clip hides the last
/// row's trailing line at the bottom edge.
class DiagnosticsRow extends StatelessWidget {
  const DiagnosticsRow({super.key, required this.label, required this.value});

  /// The row key. Already localized by the caller.
  final String label;

  /// The row value. May be data (e.g. a transport-path label) or
  /// localized copy.
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

/// A `Session` group with an empty-state (a bold title + a description
/// span), shown when no session is active.
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

/// An empty-state body: a bold title + a description span.
/// Public so the "Mesh booting" empty-state shares the exact layout with
/// the no-session empty-state (DRY).
class DiagnosticsEmptyState extends StatelessWidget {
  const DiagnosticsEmptyState({
    super.key,
    required this.title,
    required this.description,
  });

  /// The bold title.
  final String title;

  /// The description span.
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

/// A conversation's details, mesh and event log share one section layout.
class ConversationDiagnosticsSections extends StatelessWidget {
  const ConversationDiagnosticsSections({
    super.key,
    required this.label,
    required this.rows,
    required this.mesh,
    required this.events,
    this.libraryInfo,
    this.peerMossId,
  });

  final String label;
  final List<(String, String)> rows;
  final MeshInfo? mesh;
  final List<SnapshotEvent> events;
  final MossLibraryInfo? libraryInfo;
  final String? peerMossId;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DiagnosticsGroup(label: label, rows: rows),
          MeshDiagnostics(
              mesh: mesh, libraryInfo: libraryInfo, peerMossId: peerMossId),
          EventLog(events: events),
        ],
      );
}

class SessionDiagnostics extends StatelessWidget {
  const SessionDiagnostics(
      {super.key, required this.session, this.libraryInfo});

  final SessionSnapshot session;
  final MossLibraryInfo? libraryInfo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ConversationDiagnosticsSections(
      label: l.diagConversationDetails,
      mesh: session.mesh,
      events: session.events,
      libraryInfo: libraryInfo,
      peerMossId: session.peerMossId,
      rows: [
        (
          l.diagRowPeer,
          session.peerDisplayName.isNotEmpty
              ? session.peerDisplayName
              : l.diagPeerUnknown
        ),
        (l.diagRowMlsState, dmStateLabel(l, session.state)),
        (l.diagRowTransport, transportLabel(l, session.transport)),
        (
          l.diagRowPeerId,
          session.peerMossId == null
              ? l.diagPeerIdUnknown
              : shorten(session.peerMossId!, 8)
        ),
        (
          l.diagRowLastConnect,
          switch (session.lastConnectOutcome) {
            null => l.diagConnectNotYet,
            ConnectOutcome.requested => l.diagConnectRequested,
            ConnectOutcome.failed => l.diagConnectFailed,
          }
        ),
        (l.diagRowRole, session.role),
        (l.diagRowDisplay, session.displayName),
        (l.diagSessionLabel, shorten(session.sessionId, 14)),
      ],
    );
  }
}
