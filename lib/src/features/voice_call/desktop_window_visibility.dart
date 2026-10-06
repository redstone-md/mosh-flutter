import 'package:window_manager/window_manager.dart' show windowManager;

/// Preserve a visible window's geometry when bringing it to the foreground.
Future<void> bringDesktopWindowForward() async {
  if (await windowManager.isMinimized()) await windowManager.restore();
  await windowManager.show();
  await windowManager.focus();
}
