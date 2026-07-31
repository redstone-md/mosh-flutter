/// Pure UI-helper: text formatting utilities.
///
/// Ported 1:1 from `src/features/private-dm/format.ts` per ADR 0012. The TS
/// module is trivial (two functions, no Intl/NumberFormat/DateTime usage),
/// so this Dart port is equally trivial — no locale-aware formatting is
/// required here. Kept free of Flutter dependencies for unit testing.
library;

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

/// Renders an unknown caught value as a human-readable string, mirroring
/// the TS `readableError`: `Error` instances yield their message, anything
/// else is coerced via `String(error)` (Dart: `.toString()`).
String readableError(Object? error) {
  return error.toString();
}
