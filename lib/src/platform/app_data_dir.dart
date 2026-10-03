import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mosh/src/rust/api/private_dm.dart' as api show setAppDataDir;
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

/// The dir resolved by `setAppDataDirBridge()`, or `null` before it runs.
/// `mobile_dek._historyRedbPath()` reads this so its DB-exists check agrees
/// with the path Rust opens. Module-level (not a class) so the bridge and
/// the DEK path share one mutable cell without plumbing it through every
/// caller.
String? _resolvedAppDataDir;

/// The app-private data directory bridged to Rust, or `null` before
/// `setAppDataDirBridge()` has run. Callers that need the dir BEFORE the
/// bridge ran should fall back themselves (see `mobile_dek._historyRedbPath`).
String? appDataDir() => _resolvedAppDataDir;

/// Resolve the app-private data directory. Returns the directory path.
///
/// [supportDir] is the platform seam; in production it defaults to
/// `getApplicationSupportDirectory()` (path_provider). Injecting it lets the
/// fallback branch be unit-tested on a host without the plugin (the test
/// passes a getter that throws `MissingPlatformDirectoryException`). On
/// success, returns the resolved path. If the seam throws, falls back to a
/// `mosh` subdir under `Directory.systemTemp` (the pre-M-5 behavior) and logs
/// the cause so a device log makes the fallback obvious.
Future<String> resolveAppDataDir({
  Future<Directory> Function() supportDir = getApplicationSupportDirectory,
}) async {
  try {
    final Directory dir = await supportDir();
    return dir.path;
  } catch (error, stackTrace) {
    // MissingPlatformDirectoryException (or any platform failure) -> keep the
    // app running via the temp fallback rather than crashing startup. The
    // cause is logged so a device log surfaces it; the fallback matches the
    // pre-M-5 Rust behavior so DBs written before the bridge stay readable.
    debugPrint(
      'mosh: getApplicationSupportDirectory() failed; '
      'falling back to temp/mosh for app_data_dir. '
      'error=$error\n$stackTrace',
    );
    final Directory fallback =
        Directory('${Directory.systemTemp.path}${Platform.pathSeparator}mosh');
    return fallback.path;
  }
}

/// Resolve the app_data_dir, hand it to Rust via the frb `setAppDataDir`
/// bridge call, AND cache it in `appDataDir()` so `mobile_dek` reuses the
/// SAME path. Called from `main()` AFTER `RustLib.init()` and BEFORE
/// `initMobileDek()` + `runApp`, on ALL platforms. The Rust side is
/// idempotent-once (a second call returns Err), so this must run exactly once
/// per process; `main()`'s ordering guarantees that.
///
/// Rethrows the frb error if Rust rejects the path (empty or already set) so
/// startup surfaces the failure loudly rather than silently degrading to temp
/// on the Dart side while Rust keeps temp -- that divergence would orphan the
/// DEK-existence check. In practice Rust accepts the path here because this
/// is the only caller and `resolveAppDataDir` never returns an empty string
/// (systemTemp is always non-empty on every platform).
Future<void> setAppDataDirBridge() async {
  final String path = await resolveAppDataDir();
  await api.setAppDataDir(path: path);
  _resolvedAppDataDir = path;
}
