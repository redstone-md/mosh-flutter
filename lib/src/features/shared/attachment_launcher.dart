// Injectable platform seam for opening a downloaded attachment with the OS
// default application. Screens own calling this adapter and presenting errors.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

abstract interface class AttachmentLauncher {
  Future<void> open(String localPath);
}

typedef AttachmentLaunchFunction = Future<bool> Function(Uri uri);

final class UrlLauncherAttachmentLauncher implements AttachmentLauncher {
  const UrlLauncherAttachmentLauncher({
    this.isDesktop,
    this.launch,
  });

  /// Injectable for unit tests; production uses the Flutter platform signal.
  final bool? isDesktop;

  /// Injectable to test the adapter without calling a native plugin.
  final AttachmentLaunchFunction? launch;

  @override
  Future<void> open(String localPath) async {
    if (!(isDesktop ?? _isDesktopPlatform())) {
      throw UnsupportedError(
        'Opening downloaded files is supported on Windows, macOS, and Linux.',
      );
    }
    final launched = await (launch ?? _launchFile)(Uri.file(localPath));
    if (!launched) {
      throw StateError('Could not open attachment: $localPath');
    }
  }
}

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

final attachmentLauncherProvider = Provider<AttachmentLauncher>(
  (_) => const UrlLauncherAttachmentLauncher(),
);
