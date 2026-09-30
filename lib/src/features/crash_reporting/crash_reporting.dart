// Opt-in crash reporting (ADR 0035).
//
// The consent lives in the Rust-side consent file (its salt), reports go to
// Sentry, and every event passes the scrubber on the way out. Off by
// default; a build without `--dart-define=SENTRY_DSN=...` cannot report at
// all, so dev builds and forks never send anything.
library;

import 'dart:io' show Directory;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/platform/app_data_dir.dart' show appDataDir;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;

import 'crash_report_scrubber.dart';

const String _buildDsn = String.fromEnvironment('SENTRY_DSN');

/// The Sentry native SDK's queue and installation id (Windows/Linux). Pinned
/// into the data dir so an opt-out can delete it.
const String _nativeDatabaseDirName = 'sentry-native';

final crashReportingProvider = Provider<CrashReporting>(
  (ref) => CrashReporting(bridge: ref.watch(bridgeFacadeProvider)),
);

class CrashReporting {
  CrashReporting({
    required BridgeFacade bridge,
    this.dsn = _buildDsn,
    Future<void> Function(String dsn, String salt)? start,
    Future<void> Function()? stop,
  })  : _bridge = bridge,
        _start = start ?? _startSentry,
        _stop = stop ?? Sentry.close;

  final BridgeFacade _bridge;
  final String dsn;
  final Future<void> Function(String dsn, String salt) _start;
  final Future<void> Function() _stop;

  /// Whether this build can report at all.
  bool get available => dsn.isNotEmpty;

  Future<bool> isEnabled() async => await _bridge.crashReportingSalt() != null;

  /// Launch hook: starts reporting when the user opted in earlier, and
  /// finishes a previous opt-out's cleanup otherwise. Never throws — a
  /// broken reporter must not block launch.
  Future<void> resume() async {
    if (!available) return;
    try {
      final salt = await _bridge.crashReportingSalt();
      if (salt == null) return _deleteNativeDatabase();
      await _start(dsn, salt);
    } catch (error) {
      debugPrint('mosh: crash reporting did not start: $error');
    }
  }

  /// The settings switch. Off stops the SDK first, then forgets the consent
  /// and the unsent queue.
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await _start(dsn, await _bridge.enableCrashReporting());
      return;
    }
    await _stop();
    await _bridge.disableCrashReporting();
    await _deleteNativeDatabase();
  }
}

Future<void> _startSentry(String dsn, String salt) {
  final scrubber = CrashReportScrubber(salt: salt);
  return SentryFlutter.init((options) {
    options
      ..dsn = dsn
      ..sendDefaultPii = false
      // Breadcrumbs would replay what the user did; reports carry only the
      // failure itself.
      ..maxBreadcrumbs = 0
      ..enableAutoNativeBreadcrumbs = false
      ..enableUserInteractionBreadcrumbs = false
      ..enableUserInteractionTracing = false
      ..enableFramesTracking = false
      // Screens show message text (view hierarchy is off by default too).
      ..attachScreenshot = false
      ..nativeDatabasePath = _nativeDatabasePath()
      ..beforeSend = (event, hint) => scrubber.scrubEvent(event);
  });
}

String? _nativeDatabasePath() {
  final dir = appDataDir();
  return dir == null ? null : '$dir/$_nativeDatabaseDirName';
}

/// Best-effort: the native handler may still hold the files right after
/// `close`; the next launch's `resume` retries.
Future<void> _deleteNativeDatabase() async {
  final path = _nativeDatabasePath();
  if (path == null) return;
  try {
    final dir = Directory(path);
    if (await dir.exists()) await dir.delete(recursive: true);
  } catch (error) {
    debugPrint('mosh: sentry queue not deleted yet: $error');
  }
}
