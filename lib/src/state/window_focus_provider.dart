import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:window_manager/window_manager.dart' show windowManager;

/// Default focus check: `windowManager.isFocused()` with a try/catch that
/// degrades to `true` (focused) on error. An iPhone has no window_manager
/// host, so there the app counts as focused only while in the foreground.
/// Exposed as a top-level function so the provider body + tests share one
/// reference and the override site reads cleanly.
Future<bool> _defaultIsFocused() async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }
  try {
    return await windowManager.isFocused();
  } catch (_) {
    // No window_manager host (browser dev / a test without the platform
    // plugin): treat as focused so the badge clears + no toast fires.
    return true;
  }
}

/// The focus seam. Reads as `Future<bool> Function()`; the lifecycle
/// provider awaits `ref.read(windowFocusProvider)()`. Tests override with
/// `windowFocusProvider.overrideWithValue(() async => false)` to simulate
/// an unfocused window and `() async => true` for focused.
final windowFocusProvider = Provider<Future<bool> Function()>(
  (ref) => _defaultIsFocused,
);
