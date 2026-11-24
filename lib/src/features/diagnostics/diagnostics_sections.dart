import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/event_log.dart';
import 'package:mosh/src/features/diagnostics/mesh_diagnostics.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/features/shared/value_row.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show MossLibraryInfo;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';
import 'package:mosh/src/util/format.dart';

/// A named group of connection status: its label over a line, then what it
/// holds. [rows] are its readings, each a [ValueRow]; [children] come before
/// them (an empty state, the metrics of the network, the event log).
class DiagnosticsGroup extends StatelessWidget {
  const DiagnosticsGroup({
    super.key,
    required this.label,
    this.children = const [],
    this.rows = const [],
  });

  /// The group's name, already localized by the caller.
  final String label;
  final List<Widget> children;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge!
                    .copyWith(color: MoshColors.of(context).onSurfaceMuted)),
          ),
          const SizedBox(height: MoshSpace.s2),
          const Divider(),
          const SizedBox(height: MoshSpace.s1),
          ...children,
          for (final (label, value) in rows)
            ValueRow(label: label, value: value),
        ],
      );
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

/// What a group shows while it has no values: what is missing, and when the
/// values appear.
class DiagnosticsEmptyState extends StatelessWidget {
  const DiagnosticsEmptyState({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MoshSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: style),
          Text(description,
              style:
                  style.copyWith(color: MoshColors.of(context).onSurfaceMuted)),
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
          const SizedBox(height: MoshSpace.s6),
          MeshDiagnostics(
              mesh: mesh, libraryInfo: libraryInfo, peerMossId: peerMossId),
          const SizedBox(height: MoshSpace.s6),
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
