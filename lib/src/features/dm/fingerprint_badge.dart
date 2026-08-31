// Migration shim -- the fingerprint badge moved next to its own feature.
//
// `fingerprint_badge.dart` now lives in `lib/src/features/fingerprint/`,
// beside the fingerprint confirm surface it was ported with. This file only
// re-exports it, so every existing importer keeps compiling untouched.
//
// Transitional: point new imports at `features/fingerprint/` directly, and
// delete this shim once nothing outside `features/dm/` imports it.

library;

export 'package:mosh/src/features/fingerprint/fingerprint_badge.dart';
