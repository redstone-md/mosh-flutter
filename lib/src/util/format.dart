/// Pure UI-helper: text formatting utilities.
///
/// Two trivial functions, no Intl/NumberFormat/DateTime usage, so no
/// locale-aware formatting is required here. Kept free of Flutter widget
/// dependencies for unit testing; `readableError` imports
/// `PlatformException` from `package:flutter/services.dart` to special-case
/// method-channel errors.
library;

import 'package:flutter/services.dart' show PlatformException;

/// Ellipsizes `value` to a `head…tail` form when it exceeds `head * 2 + 1`
/// characters, otherwise returns it unchanged. An empty value renders as
/// an em dash.
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
/// Dart's `Exception` interface does not expose a public `.message`, so
/// this special-cases the two types the onboarding inline-error screens
/// actually throw -- `PlatformException` (method-channel /
/// flutter_secure_storage errors) and `StateError` (the fail-closed DEK
/// guard) -- to their bare `.message`, falling back to `.toString()` for
/// everything else. A null error yields an empty string.
String readableError(Object? error) {
  if (error is PlatformException) {
    return error.message ?? error.toString();
  }
  if (error is StateError) {
    return error.message;
  }
  return error?.toString() ?? '';
}

/// Formats a byte count as a compact human-readable string (the size
/// string the DM attachment card shows).
///
/// Rule: `total < 1024` -> `"{total} B"`; otherwise divide by 1024 through
/// the units `["KB", "MB", "GB"]`, choosing `value >= 10 ? 0 : 1` decimal
/// places. Kept pure (no Flutter deps) so it is unit-testable.
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
