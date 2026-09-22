/// The "Moss network" diagnostics section + its `Metric` sub-widget.
/// Extracted into its own file so `diagnostics_sections.dart` stays
/// under 500 lines.
///
/// `MeshDiagnostics` is the "Moss network" group; `Metric` fills its 2x2
/// grid. Reuses the shared primitives `DiagnosticsGroup` / `DiagnosticsRow` /
/// `DiagnosticsEmptyState` (from `diagnostics_sections.dart`) and the
/// pure helpers `peerCount` / `natType` / `relayStatus` / `peerBreakdown`
/// / `relayBreakdown` (from `diagnostics_helpers.dart`), plus `shorten`
/// from `lib/src/util/format.dart`.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show MossLibraryInfo;
import 'package:mosh/src/rust/conversation/mesh.dart';
import 'package:mosh/src/util/format.dart';

/// The "Moss network" diagnostics group.
///   - `mesh == null` -> a `DiagnosticsGroup` whose body is the
///     `DiagnosticsEmptyState` ("Mesh booting" title + its description).
///   - else -> the "Moss network" label, a 2x2 `Metric` grid of
///     Peers / NAT / Relay / Supernode, then 7 `DiagnosticsRow`s
///     (Advertised, Listen port, Known peers, Relay routes, Channels,
///     Mesh id, Public key) in that exact order.
///
/// Metric VALUES are data (peerCount / natType / relayStatus /
/// supernodeReady ? "ready" : "standby") and the small detail words
/// ("reported type", "can assist peers" / "not promoted") are status
/// tokens -- both kept literal. The metric LABELS, the row
/// keys, the group label, and the booting title/description are localized.
/// The Peers/NAT/Relay metric labels reuse the summary-card fact keys
/// (`summaryFactPeers` / `summaryFactNat` / `summaryFactRelay`) since the
/// strings are identical (DRY).
class MeshDiagnostics extends StatelessWidget {
  const MeshDiagnostics({
    super.key,
    required this.mesh,
    this.libraryInfo,
    this.peerMossId,
  });

  /// The session's mesh info, or `null` while the mesh is still booting.
  final MeshInfo? mesh;

  /// What the loaded moss library reports about itself (spec #5), or `null`
  /// when the caller has no library read (legacy callers, tests that only
  /// exercise the mesh rows): the library rows stay off the panel then.
  final MossLibraryInfo? libraryInfo;

  /// The active DM counterpart's moss peer id. Non-null (DM panels only) is
  /// what turns the Peer RTT row on: a channel and a group have no single
  /// counterpart, so asking about one would be a lie.
  final String? peerMossId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (mesh == null) {
      return DiagnosticsGroup(
        label: l.diagGroupMossNetwork,
        children: [
          DiagnosticsEmptyState(
            title: l.diagMeshBootingTitle,
            description: l.diagMeshBootingBody,
          ),
        ],
      );
    }
    final m = mesh!;
    final rows = <DiagnosticsRow>[
      DiagnosticsRow(
        label: l.diagRowAdvertised,
        value: m.advertisedAddr.isNotEmpty ? m.advertisedAddr : '-',
      ),
      DiagnosticsRow(
        label: l.diagRowListenPort,
        value: m.listenPort.toString(),
      ),
      DiagnosticsRow(
        label: l.diagRowKnownPeers,
        value: m.knownPeerCount.toString(),
      ),
      DiagnosticsRow(
        label: l.diagRowRelayRoutes,
        value: m.relayRouteCount.toString(),
      ),
      DiagnosticsRow(
        label: l.diagRowChannels,
        value: m.channels.isNotEmpty ? m.channels.length.toString() : '-',
      ),
      DiagnosticsRow(
        label: l.diagRowMeshId,
        value: shorten(m.meshId, 14),
      ),
      DiagnosticsRow(
        label: l.diagRowPublicKey,
        value: shorten(m.publicKey, 12),
      ),
      ..._libraryRows(l),
    ];
    return DiagnosticsGroup(
      label: l.diagGroupMossNetwork,
      children: [
        _MetricGrid(mesh: m),
        ...rows,
      ],
    );
  }

  /// The spec-#5 rows the loaded library answers for: its own version, the
  /// active counterpart's last measured RTT (DM panels only), and the field
  /// log's file. Rendered after the mesh rows; `libraryInfo == null` adds
  /// nothing, so a caller without the read keeps the panel exactly as
  /// before.
  List<DiagnosticsRow> _libraryRows(AppLocalizations l) {
    final info = libraryInfo;
    if (info == null) return const [];
    final rows = <DiagnosticsRow>[
      DiagnosticsRow(
        label: l.diagRowLibraryVersion,
        value: info.version,
      ),
      if (peerMossId != null)
        DiagnosticsRow(
          label: l.diagRowPeerRtt,
          value: info.peerRttMs == null
              ? l.diagRttUnknown
              : '${info.peerRttMs} ms',
        ),
      DiagnosticsRow(
        label: l.diagRowLogPath,
        value: info.logPath ?? '-',
      ),
    ];
    return rows;
  }
}

/// The 2x2 `Metric` grid (Peers / NAT / Relay / Supernode) inside
/// `MeshDiagnostics`. Extracted so `MeshDiagnostics.build` stays
/// readable; private to this file.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.mesh});

  final MeshInfo mesh;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Metric(
                  label: l.summaryFactPeers,
                  value: peerCount(mesh),
                  detail: peerBreakdown(mesh),
                ),
              ),
              Expanded(
                child: Metric(
                  label: l.summaryFactNat,
                  value: natType(mesh),
                  detail: 'reported type',
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Metric(
                  label: l.summaryFactRelay,
                  value: relayStatus(mesh),
                  detail: relayBreakdown(mesh),
                ),
              ),
              Expanded(
                child: Metric(
                  label: l.diagMetricSupernode,
                  value: mesh.supernodeReady ? 'ready' : 'standby',
                  detail:
                      mesh.supernodeReady ? 'can assist peers' : 'not promoted',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A metric cell: a label + a strong value + a small detail. The label is
/// muted (onSurfaceVariant), the strong value is onSurface, the small
/// detail is muted again.
class Metric extends StatelessWidget {
  const Metric({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
  });

  /// The metric label, already localized by the caller.
  final String label;

  /// The metric value, a data status token -- literal.
  final String value;

  /// The metric detail, a status token -- literal.
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9.5,
              color: muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9.5,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}
