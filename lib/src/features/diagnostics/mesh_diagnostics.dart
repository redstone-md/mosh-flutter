import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show MossLibraryInfo;
import 'package:mosh/src/rust/conversation/mesh.dart';
import 'package:mosh/src/util/format.dart';

/// Runtime mesh metrics, details and optional library diagnostics.
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
    return DiagnosticsGroup(
      label: l.diagGroupMossNetwork,
      rows: [
        (
          l.diagRowAdvertised,
          m.advertisedAddr.isNotEmpty ? m.advertisedAddr : '-'
        ),
        (l.diagRowListenPort, m.listenPort.toString()),
        (l.diagRowKnownPeers, m.knownPeerCount.toString()),
        (l.diagRowRelayRoutes, m.relayRouteCount.toString()),
        (
          l.diagRowChannels,
          m.channels.isNotEmpty ? m.channels.length.toString() : '-'
        ),
        (l.diagRowMeshId, shorten(m.meshId, 14)),
        (l.diagRowPublicKey, shorten(m.publicKey, 12)),
        ..._libraryRows(l),
      ],
      children: [_MetricGrid(mesh: m)],
    );
  }

  /// Peer RTT is meaningful only for the active DM counterpart.
  List<(String, String)> _libraryRows(AppLocalizations l) {
    final info = libraryInfo;
    if (info == null) return const [];
    return [
      (l.diagRowLibraryVersion, info.version),
      if (peerMossId != null)
        (
          l.diagRowPeerRtt,
          info.peerRttMs == null ? l.diagRttUnknown : '${info.peerRttMs} ms'
        ),
      (l.diagRowLogPath, info.logPath ?? '-'),
    ];
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
    final rows = [
      [
        Metric(
            label: l.summaryFactPeers,
            value: peerCount(mesh),
            detail: peerBreakdown(mesh)),
        Metric(
            label: l.summaryFactNat,
            value: natType(mesh),
            detail: 'reported type'),
      ],
      [
        Metric(
            label: l.summaryFactRelay,
            value: relayStatus(mesh),
            detail: relayBreakdown(mesh)),
        Metric(
            label: l.diagMetricSupernode,
            value: mesh.supernodeReady ? 'ready' : 'standby',
            detail: mesh.supernodeReady ? 'can assist peers' : 'not promoted'),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final metric in row) Expanded(child: metric)],
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
