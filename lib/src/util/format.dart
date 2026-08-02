/// Pure UI-helper: text formatting utilities.
///
/// Ported 1:1 from `src/features/private-dm/format.ts` per ADR 0012. The TS
/// module is trivial (two functions, no Intl/NumberFormat/DateTime usage),
/// so this Dart port is equally trivial — no locale-aware formatting is
/// required here. Kept free of Flutter widget dependencies for unit
/// testing; `readableError` imports `PlatformException` from
/// `package:flutter/services.dart` to special-case method-channel errors.
library;

import 'package:flutter/services.dart' show PlatformException;

/// Ellipsizes `value` to a `head…tail` form when it exceeds `head * 2 + 1`
/// characters, otherwise returns it unchanged. An empty value renders as
/// an em dash (mirrors the TS `!value` branch).
String shorten(String value, int head) {
  if (value.isEmpty) {
    return '—';
  }
  if (value.length <= head * 2 + 1) {
    return value;
  }
  return '${value.substring(0, head)}…${value.substring(value.length - 4)}';
}

/// Renders an unknown caught value as a human-readable string.
///
/// Closest practical Dart analog to the TS `readableError`
/// (`error instanceof Error ? error.message : String(error)`). Dart's
/// `Exception` interface does not expose a public `.message` (unlike TS's
/// `Error`), so a true 1:1 branch for arbitrary exceptions is not
/// achievable. Instead this special-cases the two types the onboarding
/// inline-error screens actually throw -- `PlatformException` (method-
/// channel / flutter_secure_storage errors) and `StateError` (the
/// fail-closed DEK guard) -- to their bare `.message`, falling back to
/// `.toString()` for everything else. A null error yields an empty
/// string.
String readableError(Object? error) {
  if (error is PlatformException) {
    return error.message ?? error.toString();
  }
  if (error is StateError) {
    return error.message;
  }
  return error?.toString() ?? '';
}

/// Formats a byte count as a compact human-readable string, ported 1:1
/// from the React `formatBytes(total: number)` in
/// `src/features/private-dm/attachment-utils.ts` (so the Flutter DM
/// attachment card shows the same size string the React app does).
///
/// Rule: `total < 1024` -> `"{total} B"`; otherwise divide by 1024 through
/// the units `["KB", "MB", "GB"]`, choosing `value >= 10 ? 0 : 1` decimal
/// places (React: `value.toFixed(value >= 10 ? 0 : 1)`, Dart:
/// `value.toStringAsFixed(decimals)`). Kept pure (no Flutter deps) so it
/// is unit-testable.
String formatBytes(BigInt total) {
  if (total < BigInt.from(1024)) {
    return '$total B';
  }
  const units = ['KB', 'MB', 'GB'];
  var value = total.toDouble() / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final decimals = value >= 10 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}
