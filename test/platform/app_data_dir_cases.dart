// M-5 unit test for the Dart half of the app_data_dir bridge (ADR 0010).
// Drives `resolveAppDataDir` directly with an injected `supportDir` seam so
// both branches are host-runnable with no real path_provider plugin and no
// Rust runtime -- `resolveAppDataDir` is the pure-ish async that owns the
// success-vs-fallback decision, which is where the correctness lives.
//
// The success branch is covered here by injecting a getter that returns a
// real `Directory` under `Directory.systemTemp` (so no plugin is needed);
// the production success branch uses the real `getApplicationSupportDirectory`
// (device/desktop-only, covered by integration tests). The fallback branch
// injects a getter that throws (mirrors
// `MissingPlatformDirectoryException` on a host without the plugin) and
// asserts the temp/mosh path is returned.
//
// `setAppDataDirBridge()` itself is NOT exercised here: it imports the real
// frb `api.setAppDataDir` (needs RustLib.init) and mutates the module-level
// `_resolvedAppDataDir`, so it is the device/desktop half. The decision
// logic -- which is where the path-selection correctness lives -- is fully
// covered here via `resolveAppDataDir`.

import 'dart:io' show Directory, Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/platform/app_data_dir.dart';

void main() {
  test('resolveAppDataDir returns the support dir path on success', () async {
    // Inject a getter that returns a real temp dir -- no plugin needed, but
    // it proves the success branch returns `dir.path` unchanged. The
    // production success branch uses the real `getApplicationSupportDirectory`
    // (device/desktop-only).
    final Directory expected = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}mosh-test-success');
    expected.createSync(recursive: true);
    addTearDown(() {
      if (expected.existsSync()) {
        expected.deleteSync(recursive: true);
      }
    });

    final String path =
        await resolveAppDataDir(supportDir: () async => expected);

    expect(path, expected.path,
        reason: 'success branch must return the support dir path verbatim');
  });

  test('resolveAppDataDir falls back to temp/mosh when the support dir throws',
      () async {
    // Inject a getter that throws, mirroring
    // `MissingPlatformDirectoryException` on a host without the plugin (or a
    // unit test that calls resolveAppDataDir without a registered platform
    // implementation). The fallback must be `<systemTemp>/mosh` -- the
    // pre-M-5 path -- so DBs written before the bridge stay readable.
    final String path = await resolveAppDataDir(
      supportDir: () async => throw StateError(
        'Unable to get application support directory',
      ),
    );

    final String expected =
        '${Directory.systemTemp.path}${Platform.pathSeparator}mosh';
    expect(path, expected,
        reason: 'fallback branch must return <systemTemp>/mosh');
  });
}
