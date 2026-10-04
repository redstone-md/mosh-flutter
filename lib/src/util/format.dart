import 'package:flutter/services.dart' show PlatformException;
import 'package:intl/intl.dart' show NumberFormat;

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
/// places. Callers can opt into a locale and a fixed decimal precision.
String formatBytes(BigInt total, {int? decimalPlaces, String? locale}) {
  final russian = locale?.startsWith('ru') == true;
  if (total < BigInt.from(1024)) {
    return '$total ${russian ? 'Б' : 'B'}';
  }
  final units = russian ? ['КБ', 'МБ', 'ГБ'] : ['KB', 'MB', 'GB'];
  var value = total.toDouble() / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final decimals = decimalPlaces ?? (value >= 10 ? 0 : 1);
  final formatted = locale == null
      ? value.toStringAsFixed(decimals)
      : (NumberFormat.decimalPattern(locale)
            ..minimumFractionDigits = decimals
            ..maximumFractionDigits = decimals)
          .format(value);
  return '$formatted ${units[unit]}';
}
