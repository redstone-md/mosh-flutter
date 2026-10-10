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
  bool _focused = true;
  bool _maximized = false;
  bool _fullScreen = false;
  bool _maximizeHovered = false;
  String _decorationLayout = ':minimize,maximize,close';
  double _leadingInset = 0;
  bool? _requestedMaximized;
  int _maximizeRevision = 0;
  int _pendingMaximizeRequests = 0;
  Future<void> _maximizeActions = Future.value();

  bool get focused => _focused;
  bool get maximized => _maximized;
  bool get fullScreen => _fullScreen;
  bool get maximizeHovered => _maximizeHovered;
  String get decorationLayout => _decorationLayout;
  double get leadingInset => _leadingInset;

  static Future<DesktopWindowController?> initialize(
      {TargetPlatform? platform}) async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return null;
    }
    final owner =
        DesktopWindowController(platform: platform ?? defaultTargetPlatform);
    channel.setMethodCallHandler(owner._nativeEvent);
    final config = await channel.invokeMapMethod<String, Object?>('configure');
    owner._configuration(config);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setTitle('Mosh');
    owner._maximized = await windowManager.isMaximized();
    owner._fullScreen = await windowManager.isFullScreen();
    owner._focused = await windowManager.isFocused();
    windowManager.addListener(owner);
    return owner;
  }

  void _configuration(Map<String, Object?>? config) {
    if (config?['layout'] case final String layout) _decorationLayout = layout;
    if (config?['leadingInset'] case final num inset) {
      _leadingInset = inset.toDouble();
    }
  }

  Future<void> _nativeEvent(MethodCall call) async {
    switch (call.method) {
      case 'configuration':
        _configuration(Map<String, Object?>.from(call.arguments as Map));
      case 'maximizeHover':
        _maximizeHovered = call.arguments == true;
      default:
        return;
    }
    notifyListeners();
  }

  Future<void> minimize() => windowManager.minimize();
  Future<void> close() => windowManager.close();
  Future<void> toggleMaximize() {
    final target = !(_requestedMaximized ?? _maximized);
    final revision = ++_maximizeRevision;
    _pendingMaximizeRequests++;
    _requestedMaximized = target;
    final action = _maximizeActions.then((_) async {
      await (target ? windowManager.maximize() : windowManager.unmaximize());
      final actual = await windowManager.isMaximized();
      if (revision != _maximizeRevision) return;
      _maximized = actual;
      if (actual == target) _requestedMaximized = null;
      notifyListeners();
    }).whenComplete(() => _pendingMaximizeRequests--);
    // Preserve each activation until native acknowledgement. A failed command
    // must neither poison the queue nor clear a newer user's intent.
    _maximizeActions =
        action.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return action.catchError((Object error, StackTrace stack) {
      if (revision == _maximizeRevision) _requestedMaximized = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

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
    _focused = true;
    notifyListeners();
  }

  @override
  void onWindowBlur() {
    _focused = false;
    notifyListeners();
  }

  @override
  void onWindowMaximize() {
    _maximized = true;
    if (_pendingMaximizeRequests == 0 && _requestedMaximized == true) {
      _requestedMaximized = null;
    }
    notifyListeners();
  }

  @override
  void onWindowUnmaximize() {
    _maximized = false;
    if (_pendingMaximizeRequests == 0 && _requestedMaximized == false) {
      _requestedMaximized = null;
    }
    notifyListeners();
  }

  @override
  void onWindowEnterFullScreen() {
    _fullScreen = true;
    notifyListeners();
  }

  @override
  void onWindowLeaveFullScreen() {
    _fullScreen = false;
    notifyListeners();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
