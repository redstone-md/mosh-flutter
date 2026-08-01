/// Pure mesh-summary helpers for the Diagnostics drawer, 1-в-1 with React's
/// `src/features/private-dm/DiagnosticsDrawerHelpers.ts`. This atomic ports
/// the SIX helpers that the Diagnostics drawer needs so far: `peerCount`,
/// `natType`, `relayStatus`, `pathLabel`, `peerBreakdown`, and
/// `relayBreakdown` (the last two are the `MeshDiagnostics` metric
/// details).
///
/// The remaining helpers from the React file (`compactDetail`, `formatTime`)
/// are used by the `EventLog` section (the third `SessionDiagnostics`
/// group), which is DEFERRED to a later atomic that ports `EventLog` once
/// its event-rendering surface is ported. `shorten` is reused from
/// `lib/src/util/format.dart`.
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

/// Human label for a DM's transport path, 1-в-1 with React `pathLabel(path,
/// relayReady?)`. "relayed" gets the "via supernode" suffix to make clear
/// the path is a Mesh-TURN relay (still E2E -- the supernode only sees
/// ciphertext). While the shared relay node has not converged yet
/// (`relayReady === false`) the label says so -- sends are queued, not
/// failing.
///
/// The "relayed via supernode" / "(warming up)" / "direct" / "connecting" /
/// "unknown" literals are DATA values (transport-path labels), not user
/// copy -- they match React literally and are NOT localized, mirroring the
/// React source.
String pathLabel(String path, bool? relayReady) {
  switch (path) {
    case 'relayed':
      return relayReady == false
          ? 'relayed via supernode (warming up)'
          : 'relayed via supernode';
    case 'direct':
      return 'direct';
    case 'connecting':
      return 'connecting';
    default:
      return path.isEmpty ? 'unknown' : path;
  }
}

/// Peer-connectivity breakdown for the `Peers` metric detail, 1-в-1 with
/// React `peerBreakdown(mesh)`:
/// `"${mesh.direct_peer_count} direct / ${mesh.relayed_peer_count} relayed"`.
/// Pure (no Flutter deps) so it is unit-testable. The "direct" / "relayed"
/// words are tight status tokens (matching React literally), so they are
/// NOT localized.
String peerBreakdown(MeshInfo mesh) {
  return '${mesh.directPeerCount} direct / ${mesh.relayedPeerCount} relayed';
}

/// Relay-capability breakdown for the `Relay` metric detail, 1-в-1 with
/// React `relayBreakdown(mesh)`:
/// `"${mesh.relay_capable_peer_count} capable / ${mesh.relay_route_count} routes"`.
/// Pure (no Flutter deps) so it is unit-testable. The "capable" / "routes"
/// words are tight status tokens (matching React literally), so they are
/// NOT localized.
String relayBreakdown(MeshInfo mesh) {
  return '${mesh.relayCapablePeerCount} capable / ${mesh.relayRouteCount} routes';
}
