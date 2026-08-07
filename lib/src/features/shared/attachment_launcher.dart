// Injectable platform seam for opening a downloaded attachment with the OS
// default application. Screens own calling this adapter and presenting errors.
//
// Dispatch by platform:
//   - Desktop (Windows/macOS/Linux) uses url_launcher's external-app mode
//     (unchanged from the original behavior).
//   - Android uses open_filex, which builds the ACTION_VIEW Intent + the
//     FileProvider content URI from the FileProvider infra landed in atomic #1.
//   - Web throws UnsupportedError (open_filex is not meaningful on web).
//
// Renamed from `UrlLauncherAttachmentLauncher` -> `AttachmentLauncherImpl`
// because the class now dispatches across url_launcher AND open_filex, so the
// old name was a misnomer. Call sites only reference the
// `attachmentLauncherProvider` instance, never the class name, so the rename
// is internal-only (no production churn). The decision was made over leaving
// the misleading name, per the "long-term architecture" principle.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

abstract interface class AttachmentLauncher {
  Future<void> open(String localPath);
}

typedef AttachmentLaunchFunction = Future<bool> Function(Uri uri);
typedef AttachmentOpenFilexFunction = Future<OpenResult> Function(String path);

final class AttachmentLauncherImpl implements AttachmentLauncher {
  const AttachmentLauncherImpl({
    this.isDesktop,
    this.isAndroid,
    this.isWeb,
    this.launch,
    this.openFilex,
  });

  /// Injectable for unit tests; production uses the Flutter platform signal.
  final bool? isDesktop;

  /// Injectable for unit tests; production uses the Flutter platform signal.
  /// Drives the open_filex (Android) branch.
  final bool? isAndroid;

  /// Injectable for unit tests; production uses `kIsWeb`. Web is an edge that
  /// never fires in the app but is guarded for completeness.
  final bool? isWeb;

  /// Injectable to test the desktop (url_launcher) path without a native
  /// plugin call.
  final AttachmentLaunchFunction? launch;

  /// Injectable to test the Android (open_filex) path without a native plugin
  /// call. Defaults to `OpenFilex.open`.
  final AttachmentOpenFilexFunction? openFilex;

  @override
  Future<void> open(String localPath) async {
    if (isWeb ?? kIsWeb) {
      throw UnsupportedError(
        'Opening downloaded files is not supported on the web.',
      );
    }
    final android = isAndroid ?? _isAndroidPlatform();
    if (android) {
      final result = await (openFilex ?? OpenFilex.open)(localPath);
      if (result.type != ResultType.done) {
        throw StateError(
          'Could not open attachment: $localPath (${result.type}: ${result.message})',
        );
      }
      return;
    }
    final desktop = isDesktop ?? _isDesktopPlatform();
    if (!desktop) {
      throw UnsupportedError(
        'Opening downloaded files is supported on Windows, macOS, Linux, and '
        'Android.',
      );
    }
    final launched = await (launch ?? _launchFile)(Uri.file(localPath));
    if (!launched) {
      throw StateError('Could not open attachment: $localPath');
    }
  }
}

bool _isAndroidPlatform() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool _isDesktopPlatform() {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux =>
      true,
    _ => false,
  };
}

Future<bool> _launchFile(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

// Backwards-compat alias retained for any external/legacy references; the
// canonical name is now `AttachmentLauncherImpl`.
typedef UrlLauncherAttachmentLauncher = AttachmentLauncherImpl;

final attachmentLauncherProvider = Provider<AttachmentLauncher>(
  (_) => const AttachmentLauncherImpl(),
);
