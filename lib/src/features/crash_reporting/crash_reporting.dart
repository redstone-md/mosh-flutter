import 'dart:async' show FutureOr, StreamSubscription;
import 'dart:convert' show jsonDecode;
import 'dart:io' show Directory;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show PanicException;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/platform/app_data_dir.dart' show appDataDir;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;

import 'crash_report_scrubber.dart';

const String _buildDsn = String.fromEnvironment('SENTRY_DSN');

/// The Sentry native SDK's queue and installation id (Windows/Linux). Pinned
/// into the data dir so an opt-out can delete it.
const String _nativeDatabaseDirName = 'sentry-native';

/// The app-wide reporter. `main` overrides it with the instance it resumed
/// at launch, so the switch stops the same Rust panic stream it started.
final crashReportingProvider = Provider<CrashReporting>(
  (ref) => CrashReporting(bridge: ref.watch(bridgeFacadeProvider)),
);

class CrashReporting {
  CrashReporting({
    required BridgeFacade bridge,
    this.dsn = _buildDsn,
    Future<void> Function(String dsn, String salt)? start,
    Future<void> Function()? stop,
    FutureOr<void> Function(SentryEvent event)? capture,
  })  : _bridge = bridge,
        _start = start ?? _startSentry,
        _stop = stop ?? Sentry.close,
        _capture = capture ?? Sentry.captureEvent;

  final BridgeFacade _bridge;
  final String dsn;
  final Future<void> Function(String dsn, String salt) _start;
  final Future<void> Function() _stop;
  final FutureOr<void> Function(SentryEvent event) _capture;
  StreamSubscription<String>? _rustPanics;

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
      await _begin(salt);
    } catch (error) {
      debugPrint('mosh: crash reporting did not start: $error');
    }
  }

  /// The settings switch. Off stops the SDK first, then forgets the consent
  /// and the unsent queue. A failed start is rolled back to off, so a switch
  /// the user sees off never reports on the next launch.
  Future<void> setEnabled(bool enabled) async {
    if (!enabled) return _end();
    try {
      await _begin(await _bridge.enableCrashReporting());
    } catch (_) {
      await _end();
      rethrow;
    }
  }

  Future<void> _end() async {
    await _rustPanics?.cancel();
    _rustPanics = null;
    await _bridge.stopPanicReporting();
    await _stop();
    await _bridge.disableCrashReporting();
    await _deleteNativeDatabase();
  }

  Future<void> _begin(String salt) async {
    await _start(dsn, salt);
    await _rustPanics?.cancel();
    _rustPanics = _bridge.startPanicReporting(dsn: dsn).listen(
          (json) => _capture(rustEventFromJson(json)),
          onError: (Object error) =>
              debugPrint('mosh: rust panic capture failed: $error'),
        );
  }
}

/// Parses a Rust-captured event. The Rust SDK writes `timestamp` as epoch
/// seconds; the Dart SDK reads an ISO string.
@visibleForTesting
SentryEvent rustEventFromJson(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  final timestamp = map['timestamp'];
  if (timestamp is num) {
    map['timestamp'] = DateTime.fromMicrosecondsSinceEpoch(
      (timestamp * Duration.microsecondsPerSecond).round(),
      isUtc: true,
    ).toIso8601String();
  }
  return SentryEvent.fromJson(map);
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
      // A panic inside a bridge call also surfaces in Dart as a
      // PanicException; the Rust capture of it carries the real backtrace.
      ..beforeSend = (event, hint) =>
          event.throwable is PanicException ? null : scrubber.scrubEvent(event);
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
