import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Owns UI polling without changing the native transport's lifetime.
/// Android resumes with an immediate read; desktops keep polling when hidden.
final class ForegroundPoller {
  ForegroundPoller(Duration interval, VoidCallback refresh)
      : _interval = interval,
        _refresh = refresh {
    if (defaultTargetPlatform == TargetPlatform.android) {
      _listener = AppLifecycleListener(onStateChange: _changed);
      _foreground = _visible(WidgetsBinding.instance.lifecycleState);
    }
    _start();
  }

  final Duration _interval;
  final VoidCallback _refresh;
  AppLifecycleListener? _listener;
  Timer? _timer;
  bool _foreground = true;

  bool get isForeground => _foreground;

  // Inactive still has a visible view, including biometric/file-picker prompts.
  static bool _visible(AppLifecycleState? state) =>
      state != AppLifecycleState.hidden && state != AppLifecycleState.paused;

  void _start() {
    if (_foreground) _timer ??= Timer.periodic(_interval, (_) => _refresh());
  }

  void _changed(AppLifecycleState state) {
    final wasForeground = _foreground;
    if (!_visible(state) || state == AppLifecycleState.detached) {
      _foreground = false;
      _timer?.cancel();
      _timer = null;
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _start();
      if (!wasForeground) _refresh();
    }
  }

  void dispose() {
    _timer?.cancel();
    _listener?.dispose();
  }
}
