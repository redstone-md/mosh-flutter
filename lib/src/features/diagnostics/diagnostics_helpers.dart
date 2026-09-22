/// Pure helpers for the Diagnostics drawer: `peerCount`, `natType`,
/// `relayStatus`, `pathLabel`, `peerBreakdown`, and `relayBreakdown`
/// (the `MeshDiagnostics` metric details), plus `formatTime` and
/// `compactDetail` (the `EventLog` section helpers). `shorten` is reused
/// from `lib/src/util/format.dart`.
library;

import 'dart:convert';

import 'package:mosh/src/rust/conversation/mesh.dart';

/// Mesh peer count as a summary string; "booting" while there is no mesh
/// snapshot yet. The "booting" literal is data, not localized.
String peerCount(MeshInfo? mesh) {
  if (mesh == null) return 'booting';
  return mesh.peerCount.toString();
}

/// NAT type label; an empty or missing type falls back to "unknown".
/// The "unknown" literal is data, not localized.
String natType(MeshInfo? mesh) {
  final raw = mesh?.natType;
  if (raw == null || raw.isEmpty) return 'unknown';
  return raw;
}

/// Relay state summary with a 4-tier fallback:
///   1. relaySessionCount > 0 -> "{n} active"
///   2. relayedPeerCount > 0  -> "{n} relayed"
///   3. relayCapablePeerCount > 0 -> "{n} capable"
///   4. else                   -> "none"
/// The "{n} active|relayed|capable" and "none" literals are data, not
/// localized.
String relayStatus(MeshInfo mesh) {
  if (mesh.relaySessionCount > 0) return '${mesh.relaySessionCount} active';
  if (mesh.relayedPeerCount > 0) return '${mesh.relayedPeerCount} relayed';
  if (mesh.relayCapablePeerCount > 0) {
    return '${mesh.relayCapablePeerCount} capable';
  }
  return 'none';
}

/// Peer-connectivity breakdown for the `Peers` metric detail:
/// "{direct} direct / {relayed} relayed". Pure (no Flutter deps) so it is
/// unit-testable. The "direct" / "relayed" words are status tokens, not
/// localized.
String peerBreakdown(MeshInfo mesh) {
  return '${mesh.directPeerCount} direct / ${mesh.relayedPeerCount} relayed';
}

/// Relay-capability breakdown for the `Relay` metric detail:
/// "{capable} capable / {routes} routes". Pure (no Flutter deps) so it is
/// unit-testable. The "capable" / "routes" words are status tokens, not
/// localized.
String relayBreakdown(MeshInfo mesh) {
  return '${mesh.relayCapablePeerCount} capable / ${mesh.relayRouteCount} routes';
}

/// Local-time `HH:mm:ss` for a `SnapshotEvent.epoch_millis`; a null or zero
/// epoch renders "-". Uses local timezone components and a manual
/// two-digit pad.
///
/// The output is plain digits with no locale formatting -- not `intl`
/// `DateFormat.Hms`, which would inject a localized separator. Pure (no
/// Flutter deps) so it is unit-testable.
String formatTime(BigInt? epochMillis) {
  if (epochMillis == null || epochMillis == BigInt.zero) return '-';
  final date = DateTime.fromMillisecondsSinceEpoch(
    epochMillis.toInt(),
  ).toLocal();
  return '${_pad(date.hour)}:${_pad(date.minute)}:${_pad(date.second)}';
}

/// Two-digit zero-pad for `formatTime`.
String _pad(int value) => value < 10 ? '0$value' : value.toString();

/// Compacts an event's `detail_json` into a `k=v k=v` summary:
///   - empty raw        -> ""
///   - JSON object      -> entries as `k=v` joined by " " (a nested object
///                         or array value -> `k=JSON-encoded(value)`;
///                         a scalar -> `k=String(value)`).
///   - JSON array       -> index/value pairs: `0=v 1=v ...`.
///   - JSON scalar      -> `String(parsed)` (a number, string, or bool).
///   - JSON `null`      -> "null".
///   - invalid JSON     -> the raw string unchanged (catch fallback).
///
/// Dart nuance: `jsonDecode` returns `dynamic` -- `Map<String, dynamic>`
/// for objects, `List` for arrays, `num`/`String`/`bool`/`null` for
/// scalars -- so we branch on `Map` / `List` / else. Pure (no Flutter
/// deps) so it is unit-testable.
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
    // not "42.0".
    return _scalar(parsed);
  } catch (_) {
    return raw;
  }
}

/// Renders a scalar as a display string: a whole-valued double (e.g. 42.0)
/// renders as its int form ("42"), not "42.0". Other
/// num/String/bool/null values pass through `.toString()`.
String _scalar(Object? v) {
  if (v is num && v == v.toInt()) return v.toInt().toString();
  return v.toString();
}
