/// Pure mesh-summary helpers for the Diagnostics drawer, 1-в-1 with React's
/// `src/features/private-dm/DiagnosticsDrawerHelpers.ts`. This atomic ports
/// the THREE helpers that the DM branch of `diagnosticsSummary` needs:
/// `peerCount`, `natType`, and `relayStatus`.
///
/// The other helpers from the React file (`peerBreakdown`, `relayBreakdown`,
/// `pathLabel`, `compactDetail`, `formatTime`, `shorten`) are used by the
/// full DiagnosticsDrawer sections (peer/mesh/event breakdowns), not by the
/// summary card. They are DEFERRED to a later atomic that ports the rest of
/// the drawer once the channel/group contracts land in the Flutter fork.
library;

import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Mesh peer count as a summary string. Mirrors React
/// `peerCount(mesh)`: `mesh == null ? "booting" : String(mesh.peer_count)`.
/// The "booting" literal is data (not localized) to match React exactly.
String peerCount(MeshInfo? mesh) {
  if (mesh == null) return 'booting';
  return mesh.peerCount.toString();
}

/// NAT type label. Mirrors React `natType(mesh)`:
/// `mesh?.nat_type || "unknown"` -- an empty-string NAT type falls back to
/// "unknown" (the JS `||` treats `""` as falsy). The "unknown" literal is
/// data (not localized) to match React exactly.
String natType(MeshInfo? mesh) {
  final raw = mesh?.natType;
  if (raw == null || raw.isEmpty) return 'unknown';
  return raw;
}

/// Relay state summary with a 4-tier fallback, 1-в-1 with React
/// `relayStatus(mesh)`:
///   1. relaySessionCount > 0 -> "{n} active"
///   2. relayedPeerCount > 0  -> "{n} relayed"
///   3. relayCapablePeerCount > 0 -> "{n} capable"
///   4. else                   -> "none"
/// The "{n} active|relayed|capable" and "none" literals are data (not
/// localized) to match React exactly.
String relayStatus(MeshInfo mesh) {
  if (mesh.relaySessionCount > 0) return '${mesh.relaySessionCount} active';
  if (mesh.relayedPeerCount > 0) return '${mesh.relayedPeerCount} relayed';
  if (mesh.relayCapablePeerCount > 0) {
    return '${mesh.relayCapablePeerCount} capable';
  }
  return 'none';
}
