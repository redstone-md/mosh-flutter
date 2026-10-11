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

/// Swaps the running bundle for the downloaded one through a detached script.
///
/// The image carries the app and an Applications link, so installing is a
/// bundle swap: the script waits for this process to leave, mounts the image,
/// stages the new bundle beside the old one, swaps them, and starts it. Every
/// step that can fail puts the previous bundle back and starts that instead, so
/// a refused swap leaves a working app rather than a missing one.
class MacOsUpdateApplier implements UpdateApplier {
  const MacOsUpdateApplier({
    String? executable,
    int Function()? processId,
    UpdateProcessStarter? start,
    UpdateProcessTerminator? terminate,
  })  : _executable = executable,
        _processId = processId ?? _currentProcessId,
        _start = start ?? _startDetached,
        _terminate = terminate ?? exit;

  /// Overridden by tests; production resolves the running bundle.
  final String? _executable;
  final int Function() _processId;
  final UpdateProcessStarter _start;
  final UpdateProcessTerminator _terminate;

  /// The bundle this process runs from: `<bundle>.app/Contents/MacOS/mosh`.
  static String bundlePath(String resolvedExecutable) =>
      File(resolvedExecutable).parent.parent.parent.path;

  /// The swap, as one script so it can outlive the process it replaces.
  /// Arguments: the app's pid, the image, and the bundle to replace. Commands
  /// come from PATH, which a macOS app keeps, so the sequence can be driven by
  /// a test's own hdiutil, ditto and open.
  static const String swapScript = r'''
#!/bin/bash
# Written by Mosh. Swaps the running bundle for the downloaded one, then starts
# it, putting the previous bundle back when a step fails.
set -u
app_pid=$1
image=$2
target=$3
staged="$target.new"
backup="$target.old"
mount=$(mktemp -d /tmp/mosh-update.XXXXXX)

detach() {
  hdiutil detach "$mount" -quiet >/dev/null 2>&1 || true
  rm -rf "$mount"
}
trap detach EXIT

fail() {
  # Nothing has changed yet, or the previous bundle is already back.
  open "$target" >/dev/null 2>&1 || true
  exit 1
}

# The bundle cannot be replaced while it runs: wait for the app to leave.
waited=0
while kill -0 "$app_pid" 2>/dev/null && [ "$waited" -lt 120 ]; do
  sleep 0.5
  waited=$((waited + 1))
done

hdiutil attach "$image" -nobrowse -readonly -mountpoint "$mount" >/dev/null || fail
source_app=$(ls -d "$mount"/*.app 2>/dev/null | head -n 1)
[ -n "$source_app" ] || fail

rm -rf "$staged" "$backup"
ditto "$source_app" "$staged" || fail
detach
rm -f "$image"

mv "$target" "$backup" || fail
if ! mv "$staged" "$target"; then
  mv "$backup" "$target" || true
  fail
fi

rm -rf "$backup"
open "$target" >/dev/null 2>&1 || true
''';

  @override
  bool get supported => true;

  @override
  Future<void> apply(File artifact) async {
    final script = File('${artifact.parent.path}/mosh-swap.sh');
    await script.writeAsString(swapScript);
    await _start(
      '/bin/bash',
      <String>[
        script.path,
        '${_processId()}',
        artifact.path,
        bundlePath(_executable ?? Platform.resolvedExecutable),
      ],
      ProcessStartMode.detached,
    );
    _terminate(0);
  }
}

/// Hosts with no installer to run: the update is a link to the release page.
class UnsupportedUpdateApplier implements UpdateApplier {
  const UnsupportedUpdateApplier();

  @override
  bool get supported => false;

  @override
  Future<void> apply(File artifact) async {}
}

int _currentProcessId() => pid;

Future<void> _startDetached(
  String executable,
  List<String> arguments,
  ProcessStartMode mode,
) async {
  await Process.start(executable, arguments, mode: mode);
}
