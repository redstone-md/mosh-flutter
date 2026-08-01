 /// Pure Diagnostics-drawer helpers, 1-в-1 with React's
 /// `src/features/private-dm/DiagnosticsDrawerHelpers.ts`. This file ports
 /// the EIGHT helpers the Diagnostics drawer needs: `peerCount`,
 /// `natType`, `relayStatus`, `pathLabel`, `peerBreakdown`, and
 /// `relayBreakdown` (the `MeshDiagnostics` metric details), plus
 /// `formatTime` and `compactDetail` (the `EventLog` section helpers --
 /// the third `SessionDiagnostics` group). `shorten` is reused from
 /// `lib/src/util/format.dart`.
 library;
 
 import 'dart:convert';
 
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
 
 /// Local-time `HH:mm:ss` for a `SnapshotEvent.epoch_millis`, 1-в-1 with
 /// React `formatTime(epoch)` in `DiagnosticsDrawerHelpers.ts`. React uses
 /// `new Date(epoch).getHours/Minutes/Seconds()` which are LOCAL timezone
 /// components, and a manual two-digit `pad`; falsy epoch (React `!epoch`,
 /// i.e. `0`/`NaN`/`null`/`undefined`) returns "-". Here the Dart contract
 /// is `BigInt epochMillis`, so the falsy check is `epoch == null ||
 /// epoch == BigInt.zero`.
 ///
 /// The output is plain digits with no locale formatting (matching React --
 /// NOT `intl` `DateFormat.Hms`, which would inject a localized
 /// separator). Pure (no Flutter deps) so it is unit-testable.
 String formatTime(BigInt? epochMillis) {
   if (epochMillis == null || epochMillis == BigInt.zero) return '-';
   final date = DateTime.fromMillisecondsSinceEpoch(
     epochMillis.toInt(),
   ).toLocal();
   return '${_pad(date.hour)}:${_pad(date.minute)}:${_pad(date.second)}';
 }
 
 /// Two-digit zero-pad for `formatTime`, 1-в-1 with React's `pad(value)`:
 /// `value < 10 ? "0" + value : String(value)`.
 String _pad(int value) => value < 10 ? '0$value' : value.toString();
 
 /// Compacts an event's `detail_json` into a `k=v k=v` summary, 1-в-1 with
 /// React `compactDetail(raw)` in `DiagnosticsDrawerHelpers.ts`:
 ///   - empty raw        -> ""
 ///   - JSON object      -> entries as `k=v` joined by " " (a nested object
 ///                         or array value -> `k=JSON.stringify(value)`;
 ///                         a scalar -> `k=String(value)`).
 ///   - JSON array       -> React treats an array as an object whose
 ///                         `Object.entries` are `[["0", v], ["1", v], ...]`,
 ///                         so the Dart-faithful mirror emits
 ///                         `0=v 1=v ...`. (JS quirk: arrays ARE objects.)
 ///   - JSON scalar      -> `String(parsed)` (a number, string, or bool).
 ///   - JSON `null`      -> React's `parsed && typeof === "object"` is falsy
 ///                         (null), so the non-object branch returns
 ///                         `String(null)` = "null".
 ///   - invalid JSON     -> the raw string unchanged (catch fallback).
 ///
 /// Dart nuance: `jsonDecode` returns `dynamic` -- `Map<String, dynamic>`
 /// for objects, `List` for arrays, `num`/`String`/`bool`/`null` for
 /// scalars. We branch on `Map` / `List` / else to mirror React's
 /// `typeof parsed === "object"` (which is true for both objects and
 /// arrays). Pure (no Flutter deps) so it is unit-testable.
String compactDetail(String raw) {
  if (raw.isEmpty) return '';
  try {
    final parsed = jsonDecode(raw);
    if (parsed is Map<String, dynamic>) {
      final entries = parsed.entries.map((entry) {
        final v = entry.value;
        if (v != null && (v is Map || v is List)) {
          return '${entry.key}=${jsonEncode(v)}';
        }
        return '${entry.key}=${_scalar(v)}';
      });
      return entries.join(' ');
    }
    if (parsed is List) {
      // Mirror React's array-as-object: Object.entries(array) gives
      // [["0", v], ["1", v], ...] -> "0=v 1=v ...".
      final entries = <String>[];
      for (var i = 0; i < parsed.length; i++) {
        final v = parsed[i];
        if (v != null && (v is Map || v is List)) {
          entries.add('$i=${jsonEncode(v)}');
        } else {
          entries.add('$i=${_scalar(v)}');
        }
      }
      return entries.join(' ');
    }
    // Scalar (num / String / bool) or null -> String(parsed). Use
    // _scalar so a whole-valued double renders as its int form ("42"),
    // matching JS `String(42.0)` rather than Dart's "42.0".
    return _scalar(parsed);
  } catch (_) {
    return raw;
  }
}

/// Renders a scalar value the way JS `String(value)` does: a whole-valued
/// double (e.g. 42.0) renders as its int form ("42"), not "42.0". Other
/// num/String/bool/null values pass through `.toString()`.
String _scalar(Object? v) {
  if (v is num && v == v.toInt()) return v.toInt().toString();
  return v.toString();
}
