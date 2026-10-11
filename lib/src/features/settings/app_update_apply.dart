import 'dart:io';

import 'app_release_provider.dart';

HostPlatform currentHostPlatform() => Platform.isWindows
    ? HostPlatform.windows
    : Platform.isMacOS
        ? HostPlatform.macOS
        : HostPlatform.other;

typedef UpdateProcessStarter = Future<void> Function(
  String executable,
  List<String> arguments,
  ProcessStartMode mode,
);

typedef UpdateProcessTerminator = void Function(int exitCode);

/// Installs a verified artifact and ends this process, so the replacement can
/// write over the files this one has open.
abstract interface class UpdateApplier {
  /// Whether this host installs the artifact on its own. About offers the
  /// update button only where this holds, and the release page otherwise.
  bool get supported;

  Future<void> apply(File artifact);
}

/// Runs the per-user installer and lets it start the new build.
///
/// `PrivilegesRequired=lowest` means no elevation prompt, and in silent mode
/// Setup closes a still-running app through Restart Manager, so the order here
/// is safe either way. `/RELAUNCH=1` is the installer's own signal to start the
/// new build once it is in place: a plain silent install stays quiet.
class WindowsUpdateApplier implements UpdateApplier {
  const WindowsUpdateApplier({
    UpdateProcessStarter? start,
    UpdateProcessTerminator? terminate,
  })  : _start = start ?? _startDetached,
        _terminate = terminate ?? exit;

  final UpdateProcessStarter _start;
  final UpdateProcessTerminator _terminate;

  static const List<String> installerArguments = <String>[
    '/SILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/RELAUNCH=1',
  ];

  @override
  bool get supported => true;

  @override
  Future<void> apply(File artifact) async {
    await _start(artifact.path, installerArguments, ProcessStartMode.detached);
    _terminate(0);
  }
}

/// Hosts where this build cannot install by itself, so the release page is the
/// honest action instead of a button that cannot finish.
///
/// macOS is the case that matters: the shipped app is sandboxed
/// (`com.apple.security.app-sandbox`), a sandboxed process can neither replace
/// the bundle in /Applications nor mount the release image, and a child process
/// inherits the sandbox. Updating there needs something outside the sandbox —
/// the pattern Sparkle's Autoupdate uses — which is its own piece of work, and
/// ADR 0045 records it.
class UnsupportedUpdateApplier implements UpdateApplier {
  const UnsupportedUpdateApplier();

  @override
  bool get supported => false;

  @override
  Future<void> apply(File artifact) async {}
}

Future<void> _startDetached(
  String executable,
  List<String> arguments,
  ProcessStartMode mode,
) async {
  await Process.start(executable, arguments, mode: mode);
}
