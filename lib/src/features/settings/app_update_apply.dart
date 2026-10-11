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

/// Puts a verified artifact where the platform can use it: an installer this
/// app runs, or — where the app cannot install anything itself — the system's
/// own handler for the downloaded image.
abstract interface class UpdateApplier {
  /// Whether this host installs on its own. About offers the update button
  /// only where this holds, and the release page otherwise.
  bool get supported;

  /// Whether [apply] replaces the installed bundle. Where it does not, the
  /// person finishes the update and the card says how.
  bool get installsInPlace;

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
  bool get installsInPlace => true;

  @override
  Future<void> apply(File artifact) async {
    await _start(artifact.path, installerArguments, ProcessStartMode.detached);
    _terminate(0);
  }
}

/// Hands the verified image to the system instead of installing it.
///
/// The shipped app is sandboxed (`com.apple.security.app-sandbox`), and a
/// sandboxed process can neither replace the bundle in /Applications nor mount
/// an image; its children inherit that. Finder mounts it outside the sandbox,
/// so the update ends with one drag — the closest to a single button this build
/// can honestly offer. Installing outright needs something running outside the
/// sandbox, the way Sparkle's Installer.xpc does, which is its own piece of work
/// (ADR 0045).
class MacOsImageApplier implements UpdateApplier {
  const MacOsImageApplier({required this.open});

  /// Opens a downloaded file with the system handler, so a test can record the
  /// hand-off instead of starting Finder.
  final Future<void> Function(String path) open;

  @override
  bool get supported => true;

  @override
  bool get installsInPlace => false;

  @override
  Future<void> apply(File artifact) => open(artifact.path);
}

/// Hosts where this build can do nothing at all with an artifact, so the release
/// page is the honest action instead of a button that cannot finish. Linux is
/// the case: the release publishes no installer for it.
class UnsupportedUpdateApplier implements UpdateApplier {
  const UnsupportedUpdateApplier();

  @override
  bool get supported => false;

  @override
  bool get installsInPlace => false;

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
