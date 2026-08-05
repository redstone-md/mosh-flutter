import 'dart:io';

import 'package:flutter/widgets.dart';

typedef DesktopProcessStarter = Future<void> Function(
  String executable,
  List<String> arguments,
  ProcessStartMode mode,
);

typedef DesktopProcessTerminator = void Function(int exitCode);

/// Relaunches the current Flutter Windows process without coupling widgets to
/// dart:io. The replacement is spawned before the current process exits.
class DesktopAppRelauncher {
  DesktopAppRelauncher({
    required List<String> arguments,
    String? executable,
    bool Function()? isWindows,
    DesktopProcessStarter? start,
    DesktopProcessTerminator? terminate,
  })  : _arguments = List.unmodifiable(arguments),
        _executable = executable ?? Platform.resolvedExecutable,
        _isWindows = isWindows ?? _isWindowsPlatform,
        _start = start ?? _startDetached,
        _terminate = terminate ?? exit;

  /// A safe fallback for widget trees mounted outside production [main].
  factory DesktopAppRelauncher.unsupported() => DesktopAppRelauncher(
        arguments: const [],
        executable: '',
        isWindows: () => false,
      );

  final List<String> _arguments;
  final String _executable;
  final bool Function() _isWindows;
  final DesktopProcessStarter _start;
  final DesktopProcessTerminator _terminate;

  /// Does nothing off Windows or when a test supplies an unsupported host.
  Future<void> relaunch() async {
    if (!_isWindows()) return;

    await _start(_executable, _arguments, ProcessStartMode.detached);
    _terminate(0);
  }

  static bool _isWindowsPlatform() => Platform.isWindows;

  static Future<void> _startDetached(
    String executable,
    List<String> arguments,
    ProcessStartMode mode,
  ) async {
    await Process.start(executable, arguments, mode: mode);
  }
}

/// Makes the production relauncher available to route descendants without
/// introducing global mutable state or changing existing widget constructors.
class DesktopAppRelauncherScope extends InheritedWidget {
  const DesktopAppRelauncherScope({
    super.key,
    required this.relauncher,
    required super.child,
  });

  final DesktopAppRelauncher relauncher;

  static DesktopAppRelauncher of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DesktopAppRelauncherScope>()
          ?.relauncher ??
      _unsupported;

  static final DesktopAppRelauncher _unsupported =
      DesktopAppRelauncher.unsupported();

  @override
  bool updateShouldNotify(DesktopAppRelauncherScope oldWidget) =>
      relauncher != oldWidget.relauncher;
}
