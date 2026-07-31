import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:win32_registry/win32_registry.dart'
    show CURRENT_USER, RegistryKey, RegistryValue;

// S2-2: Windows-side registration of the `mosh://` custom URL scheme so the
// OS launches mosh.exe (with the URI as a launch arg) when a `mosh://` link
// is opened. The Windows runner (windows/runner/main.cpp) already pipes the
// launch args to Dart via `project.set_dart_entrypoint_arguments(...)`, so
// when the OS starts `mosh.exe "mosh://invite?..."` the URI reaches Dart as
// an entrypoint argument. This module is the missing OS-association piece
// that makes the OS launch mosh.exe for a `mosh://` link in the first place
// (ADR 0009/0015: single `mosh://` scheme, desktop bundle id
// `app.mosh.desktop`, no per-fork `mosh-flutter://` variant).
//
// Scope: this task is ONLY the OS-side registration. The incoming-URI intake
// (app_links `uriLinkStream` -> route) is S2-3 and is deliberately NOT wired
// here; `app_links` is a pubspec dependency for S2-3 but is intentionally not
// imported in this module to avoid an unused-import lint (see TODO in
// main.dart).
//
// Registration is best-effort at launch:
// - Runs only on Windows (`Platform.isWindows` gate). Safe to call
//   unconditionally from `main()`; under `flutter test` (host = the test
//   machine) the gate skips it, so unit/widget tests stay green and no
//   Windows registry is touched from the test harness.
// - Writes under `HKEY_CURRENT_USER\\Software\\Classes\\mosh` (HKCU), so no
//   admin elevation is required for a dev build.
// - Idempotent: `create`/`setValue` on an existing key/value is a no-op
//   (`setValue` overwrites with the same value), so every launch re-asserts
//   the association harmlessly.
// - Never throws: every registry op is wrapped in try/catch; on failure the
//   reason is logged via `debugPrint` and the function returns normally, so
//   app startup is never blocked.
//
// API note: win32_registry 3.x exposes the predefined hives as top-level
// finals (CURRENT_USER, CLASSES_ROOT, ...) and RegistryValue as a sealed
// class with named const factories (e.g. RegistryValue.string(...)). The
// older `Registry.currentUser` / `RegistryValue(name, type, value)` form
// from the app_links README_windows.md snippet is for the pre-3.x line and
// does not compile against 3.0.3.

/// The single deep-link scheme, identical across all platforms (ADR 0015).
/// No per-fork `mosh-flutter://` variant.
const String kMoshUrlScheme = 'mosh';

/// Registers the `mosh://` custom URL scheme with Windows so the OS launches
/// this executable (passing the URI as `%1`) when a `mosh://...` link is
/// opened. Writes under `HKEY_CURRENT_USER\\Software\\Classes\\mosh` (HKCU, no
/// admin elevation needed for a dev build).
///
/// Contract:
/// - No-op on non-Windows hosts (the `Platform.isWindows` gate). Safe to call
///   unconditionally from `main()`; `flutter test` runs on the host, where it
///   is skipped.
/// - Idempotent: re-creating an existing key/value is a no-op, so every
///   launch re-asserts the association without side effects.
/// - Never throws: any registry failure is caught, logged via `debugPrint`,
///   and swallowed so app startup is never blocked.
void registerMoshUrlScheme() {
  if (!Platform.isWindows) {
    return;
  }
  // CURRENT_USER is a predefined OS-owned hive (must NOT be closed). The
  // subkeys it creates are owned handles we close when done.
  final String appPath = Platform.resolvedExecutable;
  const String scheme = kMoshUrlScheme;

  RegistryKey? protocolKey;
  try {
    // HKCU\\Software\\Classes\\<scheme> with an empty `URL Protocol` value
    // (its presence, not its content, marks the key as a URL scheme).
    protocolKey = CURRENT_USER.create('Software\\Classes\\$scheme');
    protocolKey.setValue('URL Protocol', RegistryValue.string(''));

    // shell\\open\\command default value -> "<appPath>" "%1" (the OS
    // passes the clicked URI as %1; the runner forwards it to Dart as an
    // entrypoint argument). The default (unnamed) value is written by
    // passing '' as the value name.
    final commandKey =
        protocolKey.create('shell\\open\\command');
    try {
      commandKey.setValue('', RegistryValue.string('"$appPath" "%1"'));
    } finally {
      commandKey.close();
    }
  } catch (e, st) {
    // Best-effort: a registry write failure (e.g. policy-locked HKCU, a
    // sandboxed runner, or a permissions issue) must not block app startup.
    debugPrint('mosh: failed to register mosh:// URL scheme: $e\n$st');
  } finally {
    protocolKey?.close();
  }
}
