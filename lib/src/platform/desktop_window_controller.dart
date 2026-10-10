import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Main-window operations and native caption preferences. Call children never
/// construct this owner. Runtime window events keep caption actions current.
class DesktopWindowController extends ChangeNotifier with WindowListener {
  DesktopWindowController({required this.platform});

  final TargetPlatform platform;
  static const channel = MethodChannel('mosh/window-chrome');
  bool focused = true;
  bool maximized = false;
  bool fullScreen = false;
  bool maximizeHovered = false;
  String decorationLayout = ':minimize,maximize,close';
  double leadingInset = 0;

  static Future<DesktopWindowController?> initialize(
      {TargetPlatform? platform}) async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return null;
    }
    final owner =
        DesktopWindowController(platform: platform ?? defaultTargetPlatform);
    final config = await channel.invokeMapMethod<String, Object?>('configure');
    owner._configuration(config);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setTitle('Mosh');
    owner.maximized = await windowManager.isMaximized();
    owner.fullScreen = await windowManager.isFullScreen();
    owner.focused = await windowManager.isFocused();
    windowManager.addListener(owner);
    channel.setMethodCallHandler(owner._nativeEvent);
    return owner;
  }

  void _configuration(Map<String, Object?>? config) {
    if (config?['layout'] case final String layout) decorationLayout = layout;
    if (config?['leadingInset'] case final num inset) {
      leadingInset = inset.toDouble();
    }
  }

  Future<void> _nativeEvent(MethodCall call) async {
    switch (call.method) {
      case 'configuration':
        _configuration(Map<String, Object?>.from(call.arguments as Map));
      case 'maximizeHover':
        maximizeHovered = call.arguments == true;
      default:
        return;
    }
    notifyListeners();
  }

  Future<void> minimize() => windowManager.minimize();
  Future<void> close() => windowManager.close();
  Future<void> toggleMaximize() =>
      maximized ? windowManager.unmaximize() : windowManager.maximize();
  Future<void> startDragging() => windowManager.startDragging();
  Future<void> doubleClick() => platform == TargetPlatform.macOS
      ? channel.invokeMethod<void>('doubleClick')
      : toggleMaximize();
  Future<void> showMenu() => platform == TargetPlatform.windows
      ? channel.invokeMethod<void>('showMenu')
      : windowManager.popUpWindowMenu();

  Future<void> setMaximizeRegion(Rect region, double pixelRatio) =>
      channel.invokeMethod<void>('maximizeRegion', {
        'left': region.left,
        'top': region.top,
        'right': region.right,
        'bottom': region.bottom,
        'pixelRatio': pixelRatio,
      });

  @override
  void onWindowFocus() {
    focused = true;
    notifyListeners();
  }

  @override
  void onWindowBlur() {
    focused = false;
    notifyListeners();
  }

  @override
  void onWindowMaximize() {
    maximized = true;
    notifyListeners();
  }

  @override
  void onWindowUnmaximize() {
    maximized = false;
    notifyListeners();
  }

  @override
  void onWindowEnterFullScreen() {
    fullScreen = true;
    notifyListeners();
  }

  @override
  void onWindowLeaveFullScreen() {
    fullScreen = false;
    notifyListeners();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
