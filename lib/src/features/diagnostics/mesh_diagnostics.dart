/// The React `MeshDiagnostics` "Moss network" section + its `Metric`
/// sub-widget, 1-в-1 with React's
/// `src/features/private-dm/DiagnosticsDrawerSections.tsx`. Extracted into
/// its own file so `diagnostics_sections.dart` stays under 500 lines.
///
/// In scope (this atomic): `MeshDiagnostics` (the "Moss network"
/// `.diagnostic-group`) and the `Metric` widget that fills its 2x2 grid.
/// Reuses the shared primitives `DiagnosticsGroup` / `DiagnosticsRow` /
/// `DiagnosticsEmptyState` (from `diagnostics_sections.dart`) and the
/// pure helpers `peerCount` / `natType` / `relayStatus` / `peerBreakdown`
/// / `relayBreakdown` (from `diagnostics_helpers.dart`), plus `shorten`
/// from `lib/src/util/format.dart`. `EventLog` (the third
/// `SessionDiagnostics` group) is DEFERRED to a later atomic.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';
import 'package:mosh/src/util/format.dart';

/// The React `MeshDiagnostics`: the "Moss network" `.diagnostic-group`.
/// Mirrors React's `MeshDiagnostics({ mesh })`:
///   - `mesh == null` -> a `DiagnosticsGroup` whose body is the
///     `DiagnosticsEmptyState` ("Mesh booting" title + its description).
///   - else -> the "Moss network" label, a 2x2 `Metric` grid of
///     Peers / NAT / Relay / Supernode, then 7 `DiagnosticsRow`s
///     (Advertised, Listen port, Known peers, Relay routes, Channels,
///     Mesh id, Public key) in that exact order.
///
/// Metric VALUES are data (peerCount / natType / relayStatus /
/// supernodeReady ? "ready" : "standby") and the small detail words
/// ("reported type", "can assist peers" / "not promoted") are tight status
/// tokens -- both kept literal to match React. The metric LABELS, the row
/// keys, the group label, and the booting title/description are localized.
/// The Peers/NAT/Relay metric labels reuse the summary-card fact keys
/// (`summaryFactPeers` / `summaryFactNat` / `summaryFactRelay`) since the
/// strings are identical (DRY).
class MeshDiagnostics extends StatelessWidget {
  const MeshDiagnostics({super.key, required this.mesh});

  /// The session's mesh info, or `null` while the mesh is still booting.
  final MeshInfo? mesh;

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
    ];
    return DiagnosticsGroup(
      label: l.diagGroupMossNetwork,
      children: [
        _MetricGrid(mesh: m),
        ...rows,
      ],
    );
  }
}

/// The 2x2 `Metric` grid (Peers / NAT / Relay / Supernode) inside
/// `MeshDiagnostics`. Mirrors React's `.diagnostic-mesh-grid`. Extracted so
/// `MeshDiagnostics.build` stays readable; private to this file.
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

/// The React `Metric`: a label span + a strong value + a small detail.
/// Mirrors React's `.diagnostic-metric` (a compact cell that fits a 2x2
/// grid). The label is `fg-3` (onSurfaceVariant), the strong value is
/// `fg-1` (onSurface), the small detail is `fg-3` again.
class Metric extends StatelessWidget {
  const Metric({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
  });

  /// The metric label (React `span`), already localized by the caller.
  final String label;

  /// The metric value (React `strong`), a data status token -- literal.
  final String value;

  /// The metric detail (React `small`), a status token -- literal.
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
